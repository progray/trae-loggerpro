unit LoggerPro.SQLiteAppender;

interface

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  System.DateUtils,
  System.IOUtils,
  LoggerPro,
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Option,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Phys.Intf,
  FireDAC.Phys.SQLite;

type
  TOnDBWriteError = reference to procedure(const Sender: TObject; const LogItem: TLogItem; const DBError: Exception; var RetryCount: Integer);

  TGetDBConnection = reference to function: TCustomConnection;

  TLogItemCache = record
    LogType: Integer;
    LogTag: string;
    LogMessage: string;
    TimeStamp: TDateTime;
    ThreadID: TThreadID;
  end;

  TLogItemCacheList = TList<TLogItemCache>;

  TLoggerProSQLiteAppender = class(TLoggerProAppenderBase)
  private
    const
      DEFAULT_BATCH_SIZE = 100;
      DEFAULT_FLUSH_INTERVAL_MS = 500;
      MAX_RETRY_COUNT = 5;
      DEFAULT_MAX_DB_SIZE_MB = 500;
      DEFAULT_CLEANUP_DAYS = 7;
  private
    FGetDBConnection: TGetDBConnection;
    FOnDBWriteError: TOnDBWriteError;
    FDBConnection: TFDConnection;
    FQuery: TFDQuery;
    FCache: TLogItemCacheList;
    FLock: TCriticalSection;
    FLastFlushTime: TDateTime;
    FBatchSize: Integer;
    FFlushInterval: Integer;
    FTableName: string;
    FIsFlushing: Boolean;
    FMaxDBSizeMB: Integer;
    FCleanupDays: Integer;
    FLastCleanupTime: TDateTime;
    FDatabasePath: string;
    
    procedure InitializeDatabase;
    procedure FlushCache;
    procedure ExecuteBatchInsert;
    procedure HandleDBError(const LogItem: TLogItem; const DBError: Exception; var RetryCount: Integer);
    procedure CheckAndCleanupDatabase;
    function GetDatabaseSize: Int64;
    function GetDatabasePath: string;
    procedure CleanupLogsByPriority;
    procedure CleanupOldLogs;
    procedure VacuumDatabase;
  public
    constructor Create(GetDBConnection: TGetDBConnection; OnDBWriteError: TOnDBWriteError = nil;
      BatchSize: Integer = DEFAULT_BATCH_SIZE; FlushInterval: Integer = DEFAULT_FLUSH_INTERVAL_MS;
      TableName: string = 'logs'; MaxDBSizeMB: Integer = DEFAULT_MAX_DB_SIZE_MB;
      CleanupDays: Integer = DEFAULT_CLEANUP_DAYS); reintroduce;
    destructor Destroy; override;
    procedure Setup; override;
    procedure TearDown; override;
    procedure TryToRestart(var Restarted: Boolean); override;
    procedure WriteLog(const ALogItem: TLogItem); override;
  end;

implementation

{ TLoggerProSQLiteAppender }

constructor TLoggerProSQLiteAppender.Create(GetDBConnection: TGetDBConnection; OnDBWriteError: TOnDBWriteError;
  BatchSize: Integer; FlushInterval: Integer; TableName: string; MaxDBSizeMB: Integer; CleanupDays: Integer);
begin
  inherited Create;
  FGetDBConnection := GetDBConnection;
  FOnDBWriteError := OnDBWriteError;
  FBatchSize := BatchSize;
  FFlushInterval := FlushInterval;
  FTableName := TableName;
  FMaxDBSizeMB := MaxDBSizeMB;
  FCleanupDays := CleanupDays;
  FCache := TLogItemCacheList.Create;
  FLock := TCriticalSection.Create;
  FLastFlushTime := Now;
  FIsFlushing := False;
  FLastCleanupTime := Now;
  FDatabasePath := '';
end;

destructor TLoggerProSQLiteAppender.Destroy;
begin
  FCache.Free;
  FLock.Free;
  inherited;
end;

procedure TLoggerProSQLiteAppender.Setup;
begin
  inherited;
  FDBConnection := FGetDBConnection as TFDConnection;
  FDatabasePath := GetDatabasePath;
  InitializeDatabase;
end;

procedure TLoggerProSQLiteAppender.TearDown;
begin
  inherited;
  FlushCache;
  
  if FQuery <> nil then
  begin
    FQuery.Free;
    FQuery := nil;
  end;
  
  if FDBConnection <> nil then
  begin
    FDBConnection.Connected := False;
    FDBConnection.Free;
    FDBConnection := nil;
  end;
end;

procedure TLoggerProSQLiteAppender.TryToRestart(var Restarted: Boolean);
begin
  try
    if FQuery <> nil then
    begin
      FQuery.Free;
      FQuery := nil;
    end;
    
    if FDBConnection <> nil then
    begin
      FDBConnection.Connected := False;
      FDBConnection.Free;
      FDBConnection := nil;
    end;
  except
  end;
  
  FDBConnection := FGetDBConnection as TFDConnection;
  InitializeDatabase;
  Restarted := True;
end;

procedure TLoggerProSQLiteAppender.InitializeDatabase;
var
  SQL: string;
begin
  FDBConnection.Connected := True;
  
  SQL := Format(
    'CREATE TABLE IF NOT EXISTS %s (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'log_type INTEGER NOT NULL, ' +
    'log_tag TEXT, ' +
    'log_message TEXT, ' +
    'log_timestamp DATETIME NOT NULL, ' +
    'thread_id TEXT, ' +
    'created_at DATETIME DEFAULT CURRENT_TIMESTAMP)',
    [FTableName]);
  
  FDBConnection.ExecSQL(SQL);
  
  SQL := Format('CREATE INDEX IF NOT EXISTS idx_%s_timestamp ON %s(log_timestamp)', [FTableName, FTableName]);
  FDBConnection.ExecSQL(SQL);
  
  SQL := Format('CREATE INDEX IF NOT EXISTS idx_%s_log_type ON %s(log_type)', [FTableName, FTableName]);
  FDBConnection.ExecSQL(SQL);
  
  SQL := Format('CREATE INDEX IF NOT EXISTS idx_%s_log_tag ON %s(log_tag)', [FTableName, FTableName]);
  FDBConnection.ExecSQL(SQL);
end;

function TLoggerProSQLiteAppender.GetDatabasePath: string;
begin
  Result := '';
  if Assigned(FDBConnection) and (FDBConnection.Params.Count > 0) then
  begin
    Result := FDBConnection.Params.Values['Database'];
  end;
end;

function TLoggerProSQLiteAppender.GetDatabaseSize: Int64;
begin
  Result := 0;
  if (FDatabasePath <> '') and TFile.Exists(FDatabasePath) then
  begin
    Result := TFile.GetSize(FDatabasePath);
  end;
end;

procedure TLoggerProSQLiteAppender.CheckAndCleanupDatabase;
var
  DBSize: Int64;
  MaxSizeBytes: Int64;
  HoursSinceLastCleanup: Double;
begin
  if FDatabasePath = '' then
    System.Exit;
    
  MaxSizeBytes := FMaxDBSizeMB * 1024 * 1024;
  DBSize := GetDatabaseSize;
  
  HoursSinceLastCleanup := HoursBetween(Now, FLastCleanupTime);
  
  if (DBSize > MaxSizeBytes) or (HoursSinceLastCleanup >= 24) then
  begin
    CleanupLogsByPriority;
    CleanupOldLogs;
    
    if DBSize > MaxSizeBytes then
      VacuumDatabase;
      
    FLastCleanupTime := Now;
  end;
end;

procedure TLoggerProSQLiteAppender.CleanupLogsByPriority;
var
  SQL: string;
  DBSize: Int64;
  MaxSizeBytes: Int64;
  TargetSize: Int64;
  LogTypes: array[0..4] of Integer;
  i: Integer;
  DeletedCount: Integer;
begin
  DBSize := GetDatabaseSize;
  MaxSizeBytes := FMaxDBSizeMB * 1024 * 1024;
  
  if DBSize <= MaxSizeBytes then
    System.Exit;
    
  TargetSize := MaxSizeBytes * 80 div 100;
  
  LogTypes[0] := 0; 
  LogTypes[1] := 1; 
  LogTypes[2] := 2; 
  LogTypes[3] := 3; 
  LogTypes[4] := 4; 
  
  for i := 0 to High(LogTypes) do
  begin
    if DBSize <= TargetSize then
      Break;
      
    SQL := Format(
      'DELETE FROM %s WHERE log_type = %d AND id IN (' +
      'SELECT id FROM %s WHERE log_type = %d ORDER BY log_timestamp ASC LIMIT 1000)',
      [FTableName, LogTypes[i], FTableName, LogTypes[i]]);
    
    FDBConnection.ExecSQL(SQL);
    
    DBSize := GetDatabaseSize;
  end;
end;

procedure TLoggerProSQLiteAppender.CleanupOldLogs;
var
  SQL: string;
begin
  SQL := Format(
    'DELETE FROM %s WHERE log_timestamp < datetime("now", "-%d days")',
    [FTableName, FCleanupDays]);
  FDBConnection.ExecSQL(SQL);
end;

procedure TLoggerProSQLiteAppender.VacuumDatabase;
begin
  try
    FDBConnection.ExecSQL('VACUUM');
  except
    on E: Exception do
    begin
    end;
  end;
end;

procedure TLoggerProSQLiteAppender.WriteLog(const ALogItem: TLogItem);
var
  CacheItem: TLogItemCache;
  TimeSinceLastFlush: Int64;
begin
  CacheItem.LogType := Integer(ALogItem.LogType);
  CacheItem.LogTag := ALogItem.LogTag;
  CacheItem.LogMessage := ALogItem.LogMessage;
  CacheItem.TimeStamp := ALogItem.TimeStamp;
  CacheItem.ThreadID := ALogItem.ThreadID;
  
  FLock.Enter;
  try
    FCache.Add(CacheItem);
    
    TimeSinceLastFlush := MilliSecondsBetween(Now, FLastFlushTime);
    
    if (FCache.Count >= FBatchSize) or (TimeSinceLastFlush >= FFlushInterval) then
      FlushCache;
      
    CheckAndCleanupDatabase;
  finally
    FLock.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.FlushCache;
var
  RetryCount: Integer;
  Success: Boolean;
begin
  if FIsFlushing or (FCache.Count = 0) then
    System.Exit;
    
  FIsFlushing := True;
  RetryCount := 0;
  Success := False;
  
  try
    repeat
      try
        ExecuteBatchInsert;
        Success := True;
        Break;
      except
        on E: Exception do
        begin
          if FCache.Count > 0 then
            HandleDBError(nil, E, RetryCount);
          Inc(RetryCount);
          if RetryCount >= MAX_RETRY_COUNT then
            raise;
          Sleep(100);
        end;
      end;
    until False;
  finally
    FLock.Enter;
    try
      if Success then
        FCache.Clear;
      FLastFlushTime := Now;
      FIsFlushing := False;
    finally
      FLock.Leave;
    end;
  end;
end;

procedure TLoggerProSQLiteAppender.ExecuteBatchInsert;
var
  i: Integer;
  SQL: string;
  CacheItem: TLogItemCache;
begin
  if FQuery = nil then
    FQuery := TFDQuery.Create(nil);
    
  FQuery.Connection := FDBConnection;
  
  FDBConnection.StartTransaction;
  try
    SQL := Format(
      'INSERT INTO %s (log_type, log_tag, log_message, log_timestamp, thread_id) ' +
      'VALUES (:log_type, :log_tag, :log_message, :log_timestamp, :thread_id)',
      [FTableName]);
      
    for i := 0 to FCache.Count - 1 do
    begin
      CacheItem := FCache[i];
      
      FQuery.SQL.Text := SQL;
      FQuery.ParamByName('log_type').AsInteger := CacheItem.LogType;
      FQuery.ParamByName('log_tag').AsString := CacheItem.LogTag;
      FQuery.ParamByName('log_message').AsString := CacheItem.LogMessage;
      FQuery.ParamByName('log_timestamp').AsDateTime := CacheItem.TimeStamp;
      FQuery.ParamByName('thread_id').AsString := UIntToStr(CacheItem.ThreadID);
      FQuery.ExecSQL;
    end;
    
    FDBConnection.Commit;
  except
    FDBConnection.Rollback;
    raise;
  end;
end;

procedure TLoggerProSQLiteAppender.HandleDBError(const LogItem: TLogItem; const DBError: Exception; var RetryCount: Integer);
begin
  if Assigned(FOnDBWriteError) then
    FOnDBWriteError(Self, LogItem, DBError, RetryCount);
end;

end.
