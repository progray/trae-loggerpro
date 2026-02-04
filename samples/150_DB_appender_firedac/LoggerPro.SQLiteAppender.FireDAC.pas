unit LoggerPro.SQLiteAppender.FireDAC;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,
  System.DateUtils,
  System.SyncObjs,
  Vcl.ExtCtrls,
  LoggerPro,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.DApt,
  FireDAC.Comp.Client,
  FireDAC.Comp.Script,
  Data.DB;

type
  TOnSQLiteWriteError = reference to procedure(const Sender: TObject; const LogItem: TLogItem; const DBError: Exception; var RetryCount: Integer);
  TOnSQLiteCleanup = reference to procedure(const Sender: TObject; const DeletedRecords: Integer);

  TSQLiteLogBufferItem = record
    LogType: Integer;
    LogTag: string;
    LogMessage: string;
    LogTimestamp: TDateTime;
    LogThreadID: TThreadID;
  end;

  TSQLiteLogBuffer = TList<TSQLiteLogBufferItem>;

  TLoggerProSQLiteAppenderFireDAC = class(TLoggerProAppenderBase)
  private const
    DEFAULT_BATCH_SIZE = 100;
    DEFAULT_FLUSH_INTERVAL_MS = 500;
    DEFAULT_MAX_RETRY_COUNT = 5;
    DEFAULT_CLEANUP_DAYS = 30;
    DEFAULT_DB_NAME = 'logs.db';
    SQL_CREATE_TABLE = 'CREATE TABLE IF NOT EXISTS application_logs (' +
      'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
      'log_type INTEGER NOT NULL, ' +
      'log_tag VARCHAR(100), ' +
      'log_message TEXT, ' +
      'log_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, ' +
      'log_thread_id INTEGER, ' +
      'created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
      ')';
    SQL_CREATE_INDEX_TIMESTAMP = 'CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON application_logs(log_timestamp)';
    SQL_CREATE_INDEX_TYPE = 'CREATE INDEX IF NOT EXISTS idx_logs_type ON application_logs(log_type)';
    SQL_CREATE_INDEX_TAG = 'CREATE INDEX IF NOT EXISTS idx_logs_tag ON application_logs(log_tag)';
    SQL_INSERT_LOG = 'INSERT INTO application_logs (log_type, log_tag, log_message, log_timestamp, log_thread_id) ' +
      'VALUES (:log_type, :log_tag, :log_message, :log_timestamp, :log_thread_id)';
    SQL_CLEANUP_OLD_LOGS = 'DELETE FROM application_logs WHERE log_timestamp < datetime(''now'', ''-%d days'')';
    SQL_VACUUM = 'VACUUM';
    SQL_ANALYZE = 'ANALYZE';
    SQL_WAL_CHECKPOINT = 'PRAGMA wal_checkpoint(TRUNCATE)';
  private
    FDatabasePath: string;
    FConnection: TFDConnection;
    FQuery: TFDQuery;
    FBuffer: TSQLiteLogBuffer;
    FBufferLock: TCriticalSection;
    FFlushTimer: TTimer;
    FLastFlushTime: TDateTime;
    FBatchSize: Integer;
    FFlushIntervalMS: Integer;
    FMaxRetryCount: Integer;
    FCleanupDays: Integer;
    FEnableAutoCleanup: Boolean;
    FEnableWALMode: Boolean;
    FOnSQLiteWriteError: TOnSQLiteWriteError;
    FOnSQLiteCleanup: TOnSQLiteCleanup;
    FLastCleanupTime: TDateTime;
    FCleanupIntervalHours: Integer;
    FFailedWriteCount: Integer;
    FIsShuttingDown: Boolean;

    procedure InitializeDatabase;
    procedure ConfigureSQLitePragmas;
    procedure CreateTablesIfNotExists;
    procedure FlushBuffer;
    procedure InternalFlushBuffer(Force: Boolean);
    procedure OnTimerFlush(Sender: TObject);
    procedure CleanupOldLogs;
    procedure VacuumDatabase;
    procedure HandleWriteError(const LogItem: TLogItem; const Error: Exception; var RetryCount: Integer);
    procedure ReconnectDatabase;
    function IsConnectionValid: Boolean;
    procedure EnsureConnection;
    procedure CopyBufferItems(const Source: TSQLiteLogBuffer; Dest: TSQLiteLogBuffer);
  protected
    procedure DoCleanup; virtual;
  public
    constructor Create(const ADatabasePath: string; 
                       ABatchSize: Integer;
                       AFlushIntervalMS: Integer;
                       ACleanupDays: Integer;
                       AEnableAutoCleanup: Boolean;
                       AEnableWALMode: Boolean); reintroduce; overload;
    constructor Create(const ADatabasePath: string;
                       ABatchSize: Integer;
                       AFlushIntervalMS: Integer;
                       ACleanupDays: Integer;
                       AEnableAutoCleanup: Boolean;
                       AEnableWALMode: Boolean;
                       AOnSQLiteWriteError: TOnSQLiteWriteError;
                       AOnSQLiteCleanup: TOnSQLiteCleanup); reintroduce; overload;
    destructor Destroy; override;

    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const aLogItem: TLogItem); override;
    procedure TryToRestart(var Restarted: Boolean); override;

    procedure ForceFlush;
    procedure PerformMaintenance;
    function GetLogCount: Integer;
    function GetLogs(const AStartDate, AEndDate: TDateTime; const ALogType: TLogType): TDataSet;

    property DatabasePath: string read FDatabasePath;
    property BatchSize: Integer read FBatchSize write FBatchSize;
    property FlushIntervalMS: Integer read FFlushIntervalMS write FFlushIntervalMS;
    property CleanupDays: Integer read FCleanupDays write FCleanupDays;
    property EnableAutoCleanup: Boolean read FEnableAutoCleanup write FEnableAutoCleanup;
    property EnableWALMode: Boolean read FEnableWALMode write FEnableWALMode;
    property OnSQLiteWriteError: TOnSQLiteWriteError read FOnSQLiteWriteError write FOnSQLiteWriteError;
    property OnSQLiteCleanup: TOnSQLiteCleanup read FOnSQLiteCleanup write FOnSQLiteCleanup;
    property CleanupIntervalHours: Integer read FCleanupIntervalHours write FCleanupIntervalHours;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  Winapi.Windows;

{ TLoggerProSQLiteAppenderFireDAC }

constructor TLoggerProSQLiteAppenderFireDAC.Create(const ADatabasePath: string;
  ABatchSize: Integer; AFlushIntervalMS: Integer; ACleanupDays: Integer;
  AEnableAutoCleanup: Boolean; AEnableWALMode: Boolean);
begin
  inherited Create;
  
  if ADatabasePath = '' then
    FDatabasePath := TPath.Combine(TPath.GetDocumentsPath, DEFAULT_DB_NAME)
  else
    FDatabasePath := ADatabasePath;
    
  FBatchSize := Max(1, Min(ABatchSize, 1000));
  FFlushIntervalMS := Max(100, Min(AFlushIntervalMS, 60000));
  FCleanupDays := Max(1, ACleanupDays);
  FEnableAutoCleanup := AEnableAutoCleanup;
  FEnableWALMode := AEnableWALMode;
  FMaxRetryCount := DEFAULT_MAX_RETRY_COUNT;
  FCleanupIntervalHours := 24;
  
  FBuffer := TSQLiteLogBuffer.Create;
  FBufferLock := TCriticalSection.Create;
  FLastFlushTime := Now;
  FLastCleanupTime := Now;
  FFailedWriteCount := 0;
  FIsShuttingDown := False;
  
  FFlushTimer := TTimer.Create(nil);
  FFlushTimer.Interval := FFlushIntervalMS;
  FFlushTimer.OnTimer := OnTimerFlush;
  FFlushTimer.Enabled := False;
end;

constructor TLoggerProSQLiteAppenderFireDAC.Create(const ADatabasePath: string;
  ABatchSize: Integer; AFlushIntervalMS: Integer; ACleanupDays: Integer;
  AEnableAutoCleanup: Boolean; AEnableWALMode: Boolean;
  AOnSQLiteWriteError: TOnSQLiteWriteError; AOnSQLiteCleanup: TOnSQLiteCleanup);
begin
  Create(ADatabasePath, ABatchSize, AFlushIntervalMS, ACleanupDays, AEnableAutoCleanup, AEnableWALMode);
  FOnSQLiteWriteError := AOnSQLiteWriteError;
  FOnSQLiteCleanup := AOnSQLiteCleanup;
end;

destructor TLoggerProSQLiteAppenderFireDAC.Destroy;
begin
  FIsShuttingDown := True;
  
  if FFlushTimer <> nil then
  begin
    FFlushTimer.Enabled := False;
    FFlushTimer.Free;
  end;
  
  ForceFlush;
  
  TearDown;
  
  FBufferLock.Free;
  FBuffer.Free;
  
  inherited;
end;

procedure TLoggerProSQLiteAppenderFireDAC.Setup;
begin
  inherited;
  
  InitializeDatabase;
  
  if FFlushTimer <> nil then
    FFlushTimer.Enabled := True;
end;

procedure TLoggerProSQLiteAppenderFireDAC.TearDown;
begin
  FIsShuttingDown := True;
  
  if FFlushTimer <> nil then
    FFlushTimer.Enabled := False;
    
  ForceFlush;
  
  if FQuery <> nil then
  begin
    FQuery.Free;
    FQuery := nil;
  end;
  
  if FConnection <> nil then
  begin
    if FConnection.Connected then
      FConnection.Connected := False;
    FConnection.Free;
    FConnection := nil;
  end;
  
  inherited;
end;

procedure TLoggerProSQLiteAppenderFireDAC.InitializeDatabase;
var
  LDBDir: string;
begin
  LDBDir := TPath.GetDirectoryName(FDatabasePath);
  if (LDBDir <> '') and (not TDirectory.Exists(LDBDir)) then
    TDirectory.CreateDirectory(LDBDir);
    
  FConnection := TFDConnection.Create(nil);
  FConnection.LoginPrompt := False;
  FConnection.Params.DriverID := 'SQLite';
  FConnection.Params.Database := FDatabasePath;
  
  ConfigureSQLitePragmas;
  
  FConnection.Connected := True;
  
  CreateTablesIfNotExists;
  
  FQuery := TFDQuery.Create(nil);
  FQuery.Connection := FConnection;
  FQuery.SQL.Text := SQL_INSERT_LOG;
  FQuery.Prepare;
end;

procedure TLoggerProSQLiteAppenderFireDAC.ConfigureSQLitePragmas;
begin
  if FEnableWALMode then
  begin
    FConnection.Params.Add('OpenMode=CreateUTF8');
    FConnection.Params.Add('JournalMode=WAL');
    FConnection.Params.Add('Synchronous=Normal');
  end
  else
  begin
    FConnection.Params.Add('Synchronous=Full');
  end;
  
  FConnection.Params.Add('CacheSize=10000');
  FConnection.Params.Add('PageSize=4096');
  FConnection.Params.Add('LockingMode=Normal');
  FConnection.Params.Add('BusyTimeout=30000');
  FConnection.Params.Add('ForeignKeys=ON');
  FConnection.Params.Add('TempStore=Memory');
end;

procedure TLoggerProSQLiteAppenderFireDAC.CreateTablesIfNotExists;
begin
  FConnection.ExecSQL(SQL_CREATE_TABLE);
  FConnection.ExecSQL(SQL_CREATE_INDEX_TIMESTAMP);
  FConnection.ExecSQL(SQL_CREATE_INDEX_TYPE);
  FConnection.ExecSQL(SQL_CREATE_INDEX_TAG);
end;

function TLoggerProSQLiteAppenderFireDAC.IsConnectionValid: Boolean;
begin
  Result := (FConnection <> nil) and FConnection.Connected;
  if Result then
  begin
    try
      FConnection.ExecSQLScalar('SELECT 1');
    except
      Result := False;
    end;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.EnsureConnection;
begin
  if not IsConnectionValid then
    ReconnectDatabase;
end;

procedure TLoggerProSQLiteAppenderFireDAC.ReconnectDatabase;
begin
  if FConnection <> nil then
  begin
    try
      FConnection.Connected := False;
    except
      // Ignore errors during disconnect
    end;
    
    try
      FConnection.Free;
    except
      // Ignore errors during free
    end;
    FConnection := nil;
  end;
  
  if FQuery <> nil then
  begin
    try
      FQuery.Free;
    except
      // Ignore errors during free
    end;
    FQuery := nil;
  end;
  
  InitializeDatabase;
end;

procedure TLoggerProSQLiteAppenderFireDAC.WriteLog(const aLogItem: TLogItem);
var
  LItem: TSQLiteLogBufferItem;
  LShouldFlush: Boolean;
begin
  if FIsShuttingDown then
    Exit;
    
  LItem.LogType := Integer(aLogItem.LogType);
  LItem.LogTag := aLogItem.LogTag;
  LItem.LogMessage := aLogItem.LogMessage;
  LItem.LogTimestamp := aLogItem.TimeStamp;
  LItem.LogThreadID := aLogItem.ThreadID;
  
  FBufferLock.Enter;
  try
    FBuffer.Add(LItem);
    LShouldFlush := FBuffer.Count >= FBatchSize;
  finally
    FBufferLock.Leave;
  end;
  
  if LShouldFlush then
    FlushBuffer;
end;

procedure TLoggerProSQLiteAppenderFireDAC.OnTimerFlush(Sender: TObject);
var
  LElapsedMS: Integer;
begin
  if FIsShuttingDown then
    Exit;
    
  LElapsedMS := MilliSecondsBetween(Now, FLastFlushTime);
  
  if LElapsedMS >= FFlushIntervalMS then
  begin
    FlushBuffer;
    
    if FEnableAutoCleanup and (HoursBetween(Now, FLastCleanupTime) >= FCleanupIntervalHours) then
    begin
      CleanupOldLogs;
      FLastCleanupTime := Now;
    end;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.FlushBuffer;
begin
  InternalFlushBuffer(False);
end;

procedure TLoggerProSQLiteAppenderFireDAC.ForceFlush;
begin
  InternalFlushBuffer(True);
end;

procedure TLoggerProSQLiteAppenderFireDAC.CopyBufferItems(const Source: TSQLiteLogBuffer; Dest: TSQLiteLogBuffer);
var
  I: Integer;
begin
  Dest.Clear;
  for I := 0 to Source.Count - 1 do
    Dest.Add(Source[I]);
end;

procedure TLoggerProSQLiteAppenderFireDAC.InternalFlushBuffer(Force: Boolean);
var
  LBufferCopy: TSQLiteLogBuffer;
  LItem: TSQLiteLogBufferItem;
  LRetryCount: Integer;
  LSuccess: Boolean;
  LTransactionStarted: Boolean;
  I: Integer;
  LElapsedMS: Integer;
begin
  FBufferLock.Enter;
  try
    if FBuffer.Count = 0 then
      Exit;
      
    if not Force then
    begin
      if FBuffer.Count < FBatchSize then
      begin
        LElapsedMS := MilliSecondsBetween(Now, FLastFlushTime);
        if LElapsedMS < FFlushIntervalMS then
          Exit;
      end;
    end;
    
    LBufferCopy := TSQLiteLogBuffer.Create;
    try
      CopyBufferItems(FBuffer, LBufferCopy);
      FBuffer.Clear;
    except
      LBufferCopy.Free;
      raise;
    end;
  finally
    FBufferLock.Leave;
  end;
  
  LRetryCount := 0;
  
  repeat
    try
      EnsureConnection;
      
      FConnection.StartTransaction;
      LTransactionStarted := True;
      
      try
        for I := 0 to LBufferCopy.Count - 1 do
        begin
          LItem := LBufferCopy[I];
          FQuery.ParamByName('log_type').AsInteger := LItem.LogType;
          FQuery.ParamByName('log_tag').AsString := LItem.LogTag;
          FQuery.ParamByName('log_message').AsString := LItem.LogMessage;
          FQuery.ParamByName('log_timestamp').AsDateTime := LItem.LogTimestamp;
          FQuery.ParamByName('log_thread_id').AsLargeInt := LItem.LogThreadID;
          FQuery.ExecSQL;
        end;
        
        FConnection.Commit;
        LTransactionStarted := False;
        
        FLastFlushTime := Now;
        FFailedWriteCount := 0;
      except
        on E: Exception do
        begin
          if LTransactionStarted then
          begin
            try
              FConnection.Rollback;
            except
              // Ignore rollback errors
            end;
          end;
          raise;
        end;
      end;
      
      Break;
    except
      on E: Exception do
      begin
        HandleWriteError(nil, E, LRetryCount);
        Inc(LRetryCount);
        
        if LRetryCount >= FMaxRetryCount then
        begin
          Inc(FFailedWriteCount);
          
          FBufferLock.Enter;
          try
            for I := LBufferCopy.Count - 1 downto 0 do
              FBuffer.Insert(0, LBufferCopy[I]);
          finally
            FBufferLock.Leave;
          end;
          
          Break;
        end;
        
        Sleep(Min(LRetryCount * 100, 1000));
      end;
    end;
  until False;
  
  LBufferCopy.Free;
end;

procedure TLoggerProSQLiteAppenderFireDAC.HandleWriteError(const LogItem: TLogItem;
  const Error: Exception; var RetryCount: Integer);
begin
  if Assigned(FOnSQLiteWriteError) then
    FOnSQLiteWriteError(Self, LogItem, Error, RetryCount);
end;

procedure TLoggerProSQLiteAppenderFireDAC.CleanupOldLogs;
var
  LSQL: string;
  LQuery: TFDQuery;
  LRowsAffected: Integer;
begin
  try
    EnsureConnection;
    
    LSQL := Format(SQL_CLEANUP_OLD_LOGS, [FCleanupDays]);
    
    // Use TFDQuery to get RowsAffected
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := FConnection;
      LQuery.SQL.Text := LSQL;
      LQuery.ExecSQL;
      LRowsAffected := LQuery.RowsAffected;
      
      if LRowsAffected > 0 then
      begin
        DoCleanup;
        
        if Assigned(FOnSQLiteCleanup) then
          FOnSQLiteCleanup(Self, LRowsAffected);
      end;
    finally
      LQuery.Free;
    end;
  except
    on E: Exception do
    begin
      // Log cleanup errors silently to avoid recursion
    end;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.DoCleanup;
begin
  // Can be overridden by descendants for custom cleanup logic
end;

procedure TLoggerProSQLiteAppenderFireDAC.VacuumDatabase;
begin
  try
    EnsureConnection;
    FConnection.ExecSQL(SQL_VACUUM);
    FConnection.ExecSQL(SQL_ANALYZE);
  except
    on E: Exception do
    begin
      // Ignore vacuum errors
    end;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.PerformMaintenance;
begin
  ForceFlush;
  CleanupOldLogs;
  VacuumDatabase;
end;

procedure TLoggerProSQLiteAppenderFireDAC.TryToRestart(var Restarted: Boolean);
begin
  try
    ReconnectDatabase;
    Restarted := IsConnectionValid;
  except
    Restarted := False;
  end;
end;

function TLoggerProSQLiteAppenderFireDAC.GetLogCount: Integer;
begin
  Result := 0;
  
  try
    EnsureConnection;
    Result := FConnection.ExecSQLScalar('SELECT COUNT(*) FROM application_logs');
  except
    on E: Exception do
    begin
      // Return 0 on error
    end;
  end;
end;

function TLoggerProSQLiteAppenderFireDAC.GetLogs(const AStartDate, AEndDate: TDateTime;
  const ALogType: TLogType): TDataSet;
var
  LQuery: TFDQuery;
begin
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FConnection;
    LQuery.SQL.Text := 
      'SELECT * FROM application_logs ' +
      'WHERE log_timestamp BETWEEN :start_date AND :end_date ' +
      'AND log_type >= :log_type ' +
      'ORDER BY log_timestamp DESC';
    
    LQuery.ParamByName('start_date').AsDateTime := AStartDate;
    LQuery.ParamByName('end_date').AsDateTime := AEndDate;
    LQuery.ParamByName('log_type').AsInteger := Integer(ALogType);
    
    LQuery.Open;
    Result := LQuery;
  except
    LQuery.Free;
    raise;
  end;
end;

end.
