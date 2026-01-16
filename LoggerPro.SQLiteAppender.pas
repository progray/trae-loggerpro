unit LoggerPro.SQLiteAppender;

interface

uses
  LoggerPro,
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Data.DB,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.VCLUI.Wait,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param;

type
  TOnSQLiteAppenderError = reference to procedure(const Sender: TObject; const LogItem: TLogItem; const DBError: Exception);

  TLoggerProSQLiteAppender = class(TLoggerProAppenderBase)
  private const
    DEFAULT_BATCH_SIZE = 100;
    DEFAULT_FLUSH_INTERVAL_MS = 500;
  private
    FDBPath: string;
    FBatchSize: Integer;
    FFlushIntervalMs: Integer;
    FDBConnection: TFDConnection;
    FLogCache: TThreadList<TLogItem>;
    FCriticalSection: TCriticalSection;
    FFlushTimer: TTimer;
    FLastFlushTime: TDateTime;
    FOnError: TOnSQLiteAppenderError;
    procedure InternalFlushLogCache;
    procedure EnsureTableExists;
    procedure ConfigureDatabase;
    procedure FlushTimerTick(Sender: TObject);
    function GetCurrentTimestamp: TDateTime;
  protected
    procedure WriteLog(const aLogItem: TLogItem); override;
  public
    constructor Create(const ADBPath: string; ABatchSize: Integer = DEFAULT_BATCH_SIZE;
      AFlushIntervalMs: Integer = DEFAULT_FLUSH_INTERVAL_MS; AOnError: TOnSQLiteAppenderError = nil; ALogItemRenderer: ILogItemRenderer = nil); reintroduce;
    destructor Destroy; override;
    procedure Setup; override;
    procedure TearDown; override;
    procedure TryToRestart(var Restarted: Boolean); override;
    procedure Flush;
  end;

implementation

uses
  System.DateUtils;

{ TLoggerProSQLiteAppender }

constructor TLoggerProSQLiteAppender.Create(const ADBPath: string; ABatchSize, AFlushIntervalMs: Integer;
  AOnError: TOnSQLiteAppenderError; ALogItemRenderer: ILogItemRenderer);
begin
  inherited Create(ALogItemRenderer);
  FDBPath := ADBPath;
  FBatchSize := ABatchSize;
  FFlushIntervalMs := AFlushIntervalMs;
  FOnError := AOnError;
  FLogCache := TThreadList<TLogItem>.Create;
  FCriticalSection := TCriticalSection.Create;
  FDBConnection := nil;
  FFlushTimer := nil;
  FLastFlushTime := 0;
end;

destructor TLoggerProSQLiteAppender.Destroy;
begin
  TearDown;
  FFlushTimer.Free;
  FLogCache.Free;
  FCriticalSection.Free;
  inherited;
end;

procedure TLoggerProSQLiteAppender.Setup;
begin
  inherited;
  
  ForceDirectories(ExtractFilePath(FDBPath));
  
  FDBConnection := TFDConnection.Create(nil);
  FDBConnection.LoginPrompt := False;
  FDBConnection.DriverName := 'SQLite';
  FDBConnection.Params.Add('Database=' + FDBPath);
  
  FFlushTimer := TTimer.Create(nil);
  FFlushTimer.Enabled := False;
  FFlushTimer.Interval := FFlushIntervalMs;
  FFlushTimer.OnTimer := FlushTimerTick;
  
  try
    FDBConnection.Connected := True;
    ConfigureDatabase;
    EnsureTableExists;
    FFlushTimer.Enabled := True;
  except
    on E: Exception do
    begin
      FDBConnection.Free;
      FDBConnection := nil;
      raise;
    end;
  end;
end;

procedure TLoggerProSQLiteAppender.TearDown;
begin
  if Assigned(FFlushTimer) then
    FFlushTimer.Enabled := False;
  
  Flush;
  
  if Assigned(FDBConnection) then
  begin
    FDBConnection.Connected := False;
    FDBConnection.Free;
    FDBConnection := nil;
  end;
  
  inherited;
end;

procedure TLoggerProSQLiteAppender.TryToRestart(var Restarted: Boolean);
begin
  Restarted := False;
  
  if Assigned(FDBConnection) and FDBConnection.Connected then
    Exit;
  
  try
    if Assigned(FDBConnection) then
    begin
      FDBConnection.Connected := False;
      FDBConnection.Free;
    end;
    
    FDBConnection := TFDConnection.Create(nil);
    FDBConnection.LoginPrompt := False;
    FDBConnection.DriverName := 'SQLite';
    FDBConnection.Params.Add('Database=' + FDBPath);
    FDBConnection.Connected := True;
    
    ConfigureDatabase;
    EnsureTableExists;
    
    if Assigned(FFlushTimer) then
      FFlushTimer.Enabled := True;
    
    Restarted := True;
  except
    on E: Exception do
    begin
      if Assigned(FDBConnection) then
      begin
        FDBConnection.Free;
        FDBConnection := nil;
      end;
      
      if Assigned(FOnError) then
        FOnError(Self, nil, E);
    end;
  end;
end;

procedure TLoggerProSQLiteAppender.ConfigureDatabase;
begin
  if not Assigned(FDBConnection) then
    raise ELoggerPro.Create('Database connection not initialized');
  
  FDBConnection.ExecSQL('PRAGMA journal_mode = WAL');
  FDBConnection.ExecSQL('PRAGMA synchronous = NORMAL');
end;

procedure TLoggerProSQLiteAppender.EnsureTableExists;
begin
  if not Assigned(FDBConnection) then
    raise ELoggerPro.Create('Database connection not initialized');
  
  FDBConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS loggerpro_logs (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'log_type INTEGER NOT NULL, ' +
    'log_tag TEXT NOT NULL, ' +
    'log_message TEXT NOT NULL, ' +
    'log_timestamp DATETIME NOT NULL, ' +
    'log_thread_id INTEGER NOT NULL, ' +
    'log_level TEXT GENERATED ALWAYS AS (' +
    '  CASE log_type ' +
    '    WHEN 0 THEN ''DEBUG'' ' +
    '    WHEN 1 THEN ''INFO'' ' +
    '    WHEN 2 THEN ''WARN'' ' +
    '    WHEN 3 THEN ''ERROR'' ' +
    '    WHEN 4 THEN ''FATAL'' ' +
    '    ELSE ''UNKNOWN'' ' +
    '  END' +
    ') VIRTUAL' +
    ')');
  
  FDBConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS idx_loggerpro_timestamp ON loggerpro_logs(log_timestamp)');
  FDBConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS idx_loggerpro_type ON loggerpro_logs(log_type)');
  FDBConnection.ExecSQL(
    'CREATE INDEX IF NOT EXISTS idx_loggerpro_tag ON loggerpro_logs(log_tag)');
end;

procedure TLoggerProSQLiteAppender.WriteLog(const aLogItem: TLogItem);
var
  LList: TList<TLogItem>;
  LCurrentTime: TDateTime;
  LElapsedMs: Integer;
begin
  if not Assigned(FDBConnection) or not FDBConnection.Connected then
  begin
    if Assigned(FOnError) then
      FOnError(Self, aLogItem, ELoggerPro.Create('Database connection is not available'));
    Exit;
  end;
  
  LList := FLogCache.LockList;
  try
    LList.Add(aLogItem.Clone);
  finally
    FLogCache.UnlockList;
  end;
  
  FCriticalSection.Enter;
  try
    LCurrentTime := GetCurrentTimestamp;
    LElapsedMs := MilliSecondsBetween(LCurrentTime, FLastFlushTime);
    
    LList := FLogCache.LockList;
    try
      if (LList.Count >= FBatchSize) or (LElapsedMs >= FFlushIntervalMs) then
      begin
        InternalFlushLogCache;
        FLastFlushTime := LCurrentTime;
      end;
    finally
      FLogCache.UnlockList;
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.InternalFlushLogCache;
var
  LList: TList<TLogItem>;
  LBatch: TList<TLogItem>;
  LQuery: TFDQuery;
  LLogItem: TLogItem;
  I: Integer;
begin
  LList := FLogCache.LockList;
  try
    if LList.Count = 0 then
      Exit;
    
    LBatch := TList<TLogItem>.Create;
    try
      for I := Min(LList.Count - 1, FBatchSize - 1) downto 0 do
      begin
        LBatch.Insert(0, LList[I]);
        LList.Delete(I);
      end;
      
      if LBatch.Count = 0 then
        Exit;
      
      try
        LQuery := TFDQuery.Create(nil);
        try
          LQuery.Connection := FDBConnection;
          LQuery.SQL.Text := 'INSERT INTO loggerpro_logs (log_type, log_tag, log_message, log_timestamp, log_thread_id) ' +
                            'VALUES (:log_type, :log_tag, :log_message, :log_timestamp, :log_thread_id)';
          
          FDBConnection.StartTransaction;
          try
            for LLogItem in LBatch do
            begin
              LQuery.ParamByName('log_type').AsInteger := Integer(LLogItem.LogType);
              LQuery.ParamByName('log_tag').AsString := LLogItem.LogTag;
              LQuery.ParamByName('log_message').AsString := LLogItem.LogMessage;
              LQuery.ParamByName('log_timestamp').AsDateTime := LLogItem.TimeStamp;
              LQuery.ParamByName('log_thread_id').AsInteger := LLogItem.ThreadID;
              LQuery.ExecSQL;
            end;
            FDBConnection.Commit;
          except
            FDBConnection.Rollback;
            raise;
          end;
        finally
          LQuery.Free;
        end;
      except
        on E: Exception do
        begin
          for LLogItem in LBatch do
          begin
            LList.Add(LLogItem);
            if Assigned(FOnError) then
              FOnError(Self, LLogItem, E);
          end;
          raise;
        end;
      end;
    finally
      LBatch.Free;
    end;
  finally
    FLogCache.UnlockList;
  end;
end;

procedure TLoggerProSQLiteAppender.Flush;
var
  LList: TList<TLogItem>;
begin
  FCriticalSection.Enter;
  try
    repeat
      LList := FLogCache.LockList;
      try
        if LList.Count = 0 then
          Break;
      finally
        FLogCache.UnlockList;
      end;
      
      InternalFlushLogCache;
    until False;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.FlushTimerTick(Sender: TObject);
var
  LCurrentTime: TDateTime;
  LElapsedMs: Integer;
begin
  FCriticalSection.Enter;
  try
    LCurrentTime := GetCurrentTimestamp;
    LElapsedMs := MilliSecondsBetween(LCurrentTime, FLastFlushTime);
    
    if LElapsedMs >= FFlushIntervalMs then
    begin
      InternalFlushLogCache;
      FLastFlushTime := LCurrentTime;
    end;
  finally
    FCriticalSection.Leave;
  end;
end;

function TLoggerProSQLiteAppender.GetCurrentTimestamp: TDateTime;
begin
  Result := Now;
end;

end.
