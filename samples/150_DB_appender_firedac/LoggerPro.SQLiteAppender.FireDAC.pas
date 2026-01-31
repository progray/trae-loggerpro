unit LoggerPro.SQLiteAppender.FireDAC;

interface

uses
  LoggerPro,
  System.Generics.Collections,
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.DateUtils,
  System.IOUtils,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Comp.Client,
  Data.DB;

type
  TLogBuffer = array of TLogItem;

  TLoggerProSQLiteAppender = class(TLoggerProAppenderBase)
  private const
    DEFAULT_BATCH_SIZE = 100;
    DEFAULT_FLUSH_INTERVAL_MS = 500;
    DEFAULT_MAX_LOG_AGE_DAYS = 30;
    DEFAULT_CLEANUP_INTERVAL_HOURS = 24;
    DEFAULT_DB_FILENAME = 'logs.db3';
  private
    FDBPath: string;
    FConnection: TFDConnection;
    FPhysSQLiteLink: TFDPhysSQLiteDriverLink;
    FBatchSize: Integer;
    FFlushIntervalMs: Integer;
    FMaxLogAgeDays: Integer;
    FCleanupIntervalHours: Integer;
    FBuffer: array of TLogItem;
    FBufferCount: Integer;
    FLastFlushTime: TDateTime;
    FLastCleanupTime: TDateTime;
    FCriticalSection: TCriticalSection;
    FInsertCommand: TFDCommand;
    procedure EnsureConnection;
    procedure EnsureTableExists;
    procedure ConfigureWALMode;
    procedure PerformCleanup;
    function ShouldFlush: Boolean;
    procedure FlushBuffer;
  public
    procedure Setup; override;
    procedure TearDown; override;
  public
    constructor Create(
      const ADBPath: string = '';
      ABatchSize: Integer = DEFAULT_BATCH_SIZE;
      AFlushIntervalMs: Integer = DEFAULT_FLUSH_INTERVAL_MS;
      AMaxLogAgeDays: Integer = DEFAULT_MAX_LOG_AGE_DAYS;
      ACleanupIntervalHours: Integer = DEFAULT_CLEANUP_INTERVAL_HOURS;
      ALogItemRenderer: ILogItemRenderer = nil); reintroduce;
    destructor Destroy; override;
    procedure WriteLog(const aLogItem: TLogItem); override;
  end;

implementation

{ TLoggerProSQLiteAppender }

constructor TLoggerProSQLiteAppender.Create(
  const ADBPath: string;
  ABatchSize, AFlushIntervalMs, AMaxLogAgeDays, ACleanupIntervalHours: Integer;
  ALogItemRenderer: ILogItemRenderer);
begin
  inherited Create(ALogItemRenderer);
  FDBPath := ADBPath;
  if FDBPath.IsEmpty then
    FDBPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), DEFAULT_DB_FILENAME);
  FBatchSize := ABatchSize;
  FFlushIntervalMs := AFlushIntervalMs;
  FMaxLogAgeDays := AMaxLogAgeDays;
  FCleanupIntervalHours := ACleanupIntervalHours;
  FCriticalSection := TCriticalSection.Create;
  SetLength(FBuffer, FBatchSize);
  FBufferCount := 0;
  FLastFlushTime := 0;
  FLastCleanupTime := 0;
end;

destructor TLoggerProSQLiteAppender.Destroy;
begin
  TearDown;
  FCriticalSection.Free;
  inherited;
end;

procedure TLoggerProSQLiteAppender.Setup;
begin
  inherited;
  FCriticalSection.Enter;
  try
    FPhysSQLiteLink := TFDPhysSQLiteDriverLink.Create(nil);
    FConnection := TFDConnection.Create(nil);
    FInsertCommand := TFDCommand.Create(nil);
    FInsertCommand.Connection := FConnection;
    EnsureConnection;
    EnsureTableExists;
    ConfigureWALMode;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.TearDown;
begin
  FCriticalSection.Enter;
  try
    if FBufferCount > 0 then
      FlushBuffer;
    if Assigned(FInsertCommand) then
    begin
      FInsertCommand.Free;
      FInsertCommand := nil;
    end;
    if Assigned(FConnection) then
    begin
      FConnection.Connected := False;
      FConnection.Free;
      FConnection := nil;
    end;
    if Assigned(FPhysSQLiteLink) then
    begin
      FPhysSQLiteLink.Free;
      FPhysSQLiteLink := nil;
    end;
  finally
    FCriticalSection.Leave;
  end;
  inherited;
end;

procedure TLoggerProSQLiteAppender.EnsureConnection;
begin
  if FConnection.Connected then Exit;

  FConnection.DriverName := 'SQLite';
  FConnection.Params.Database := FDBPath;
  FConnection.Params.Add('LockingMode=Normal');
  FConnection.Params.Add('JournalMode=WAL');
  FConnection.Params.Add('Synchronous=Normal');
  FConnection.Params.Add('SharedCache=True');
  FConnection.Params.Add('StringFormat=Unicode');
  FConnection.Params.Add('SQLiteAdvanced=journal_size_limit=104857600');
  FConnection.LoginPrompt := False;
  FConnection.Connected := True;
end;

procedure TLoggerProSQLiteAppender.EnsureTableExists;
var
  LCreateSQL: string;
begin
  LCreateSQL :=
    'CREATE TABLE IF NOT EXISTS logs (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    '  log_type INTEGER NOT NULL, ' +
    '  log_tag TEXT NOT NULL, ' +
    '  log_message TEXT NOT NULL, ' +
    '  log_timestamp DATETIME NOT NULL, ' +
    '  log_thread_id INTEGER NOT NULL, ' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ')';
  FConnection.ExecSQL(LCreateSQL);

  FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(log_timestamp)');
  FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_logs_type ON logs(log_type)');
  FConnection.ExecSQL('CREATE INDEX IF NOT EXISTS idx_logs_tag ON logs(log_tag)');

  FInsertCommand.CommandText.Text :=
    'INSERT INTO logs (log_type, log_tag, log_message, log_timestamp, log_thread_id) ' +
    'VALUES (:log_type, :log_tag, :log_message, :log_timestamp, :log_thread_id)';
  FInsertCommand.Prepare;
end;

procedure TLoggerProSQLiteAppender.ConfigureWALMode;
begin
  FConnection.ExecSQL('PRAGMA journal_mode=WAL');
  FConnection.ExecSQL('PRAGMA synchronous=NORMAL');
  FConnection.ExecSQL('PRAGMA temp_store=MEMORY');
  FConnection.ExecSQL('PRAGMA mmap_size=268435456');
  FConnection.ExecSQL('PRAGMA cache_size=-64000');
end;

procedure TLoggerProSQLiteAppender.PerformCleanup;
var
  LCutoffDate: TDateTime;
  LRowsAffected: Integer;
begin
  if FMaxLogAgeDays <= 0 then Exit;

  LCutoffDate := IncDay(Now, -FMaxLogAgeDays);
  LRowsAffected := FConnection.ExecSQL(
    'DELETE FROM logs WHERE log_timestamp < :cutoff',
    [LCutoffDate]);

  if LRowsAffected > 0 then
  begin
    FConnection.ExecSQL('PRAGMA wal_checkpoint(TRUNCATE)');
  end;
end;

function TLoggerProSQLiteAppender.ShouldFlush: Boolean;
var
  LNow: TDateTime;
  LElapsedMs: Integer;
begin
  LNow := Now;
  LElapsedMs := MilliSecondsBetween(LNow, FLastFlushTime);
  Result := (FBufferCount >= FBatchSize) or (LElapsedMs >= FFlushIntervalMs);
end;

procedure TLoggerProSQLiteAppender.FlushBuffer;
var
  I: Integer;
  LLogItem: TLogItem;
  LNeedsCleanup: Boolean;
begin
  if FBufferCount = 0 then Exit;

  FConnection.ExecSQL('BEGIN IMMEDIATE');
  try
    for I := 0 to FBufferCount - 1 do
    begin
      LLogItem := FBuffer[I];
      try
        FInsertCommand.ParamByName('log_type').AsInteger := Ord(LLogItem.LogType);
        FInsertCommand.ParamByName('log_tag').AsString := LLogItem.LogTag;
        FInsertCommand.ParamByName('log_message').AsString := LLogItem.LogMessage;
        FInsertCommand.ParamByName('log_timestamp').AsDateTime := LLogItem.TimeStamp;
        FInsertCommand.ParamByName('log_thread_id').AsInteger := LLogItem.ThreadID;
        FInsertCommand.Execute;
      finally
        LLogItem.Free;
      end;
    end;
    FConnection.ExecSQL('COMMIT');
  except
    FConnection.ExecSQL('ROLLBACK');
    raise;
  end;

  FBufferCount := 0;
  FLastFlushTime := Now;

  LNeedsCleanup := (FMaxLogAgeDays > 0) and
    (HoursBetween(FLastFlushTime, FLastCleanupTime) >= FCleanupIntervalHours);
  if LNeedsCleanup then
  begin
    PerformCleanup;
    FLastCleanupTime := FLastFlushTime;
  end;
end;

procedure TLoggerProSQLiteAppender.WriteLog(const aLogItem: TLogItem);
begin
  FCriticalSection.Enter;
  try
    if FBufferCount >= FBatchSize then
      FlushBuffer;

    FBuffer[FBufferCount] := aLogItem.Clone;
    Inc(FBufferCount);

    if ShouldFlush then
      FlushBuffer;
  finally
    FCriticalSection.Leave;
  end;
end;

end.
