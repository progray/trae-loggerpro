unit LoggerPro.SQLiteAppender;

interface

uses
  Winapi.Windows,
  System.Classes, 
  System.SysUtils, 
  System.Generics.Collections,
  System.SyncObjs,
  System.DateUtils,
  Vcl.Forms,
  Vcl.ExtCtrls,
  LoggerPro, 
  Data.DB,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Comp.UI,
  FireDAC.Phys.SQLite;

type
  /// <summary>
  /// High-performance SQLite Appender with batch writing and optimized SQLite settings
  /// </summary>
  TLoggerProSQLiteAppender = class(TLoggerProAppenderBase)
  private
    FConnection: TFDConnection;
    FQuery: TFDQuery;
    FConnectionString: string;
    FBatchSize: Integer;
    FFlushInterval: Integer; // in milliseconds
    FLogBuffer: TList<TLogItem>;
    FBufferLock: TCriticalSection;
    FLastFlushTime: TDateTime;
    FFlushTimer: TTimer;
    FIsShuttingDown: Boolean;
    FMaxLogAge: Integer; // in days, for log cleanup
    FLastCleanupTime: TDateTime;
    
    procedure ConfigureSQLite;
    procedure FlushBuffer;
    procedure FlushBufferToDatabase;
    procedure OnFlushTimer(Sender: TObject);
    procedure EnsureTableExists;
    procedure CleanupOldLogs;
    
  protected
    procedure InternalWriteLog(const ALogItem: TLogItem);
    
  public
    constructor Create(const AConnectionString: string; ABatchSize: Integer = 100; AFlushInterval: Integer = 500; AMaxLogAge: Integer = 30); reintroduce;
    destructor Destroy; override;
    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const ALogItem: TLogItem); override;
    procedure ForceFlush; // Explicitly flush the buffer
  end;

implementation

{ TLoggerProSQLiteAppender }

constructor TLoggerProSQLiteAppender.Create(const AConnectionString: string; 
  ABatchSize: Integer = 100; AFlushInterval: Integer = 500; AMaxLogAge: Integer = 30);
begin
  inherited Create;
  FConnectionString := AConnectionString;
  FBatchSize := ABatchSize;
  FFlushInterval := AFlushInterval;
  FMaxLogAge := AMaxLogAge;
  FLogBuffer := TList<TLogItem>.Create;
  FBufferLock := TCriticalSection.Create;
  FIsShuttingDown := False;
  FLastFlushTime := Now;
  FLastCleanupTime := Now;
end;

destructor TLoggerProSQLiteAppender.Destroy;
begin
  FIsShuttingDown := True;
  
  // Flush any remaining logs
  if FLogBuffer.Count > 0 then
  begin
    try
      FlushBufferToDatabase;
    except
      // Ignore errors during shutdown
    end;
  end;
  
  FreeAndNil(FFlushTimer);
  FreeAndNil(FLogBuffer);
  FreeAndNil(FBufferLock);
  FreeAndNil(FQuery);
  FreeAndNil(FConnection);
  
  inherited Destroy;
end;

procedure TLoggerProSQLiteAppender.Setup;
begin
  inherited Setup;
  
  // Create connection and query components
  FConnection := TFDConnection.Create(nil);
  FConnection.ConnectionString := FConnectionString;
  FConnection.Connected := True;
  
  // Configure SQLite for optimal performance
  ConfigureSQLite;
  
  // Ensure the table exists
  EnsureTableExists;
  
  // Create query for batch inserts
  FQuery := TFDQuery.Create(nil);
  FQuery.Connection := FConnection;
  FQuery.SQL.Text := 
    'INSERT INTO loggerpro_logs (log_type, log_tag, log_message, log_timestamp, log_thread_id) ' +
    'VALUES (:log_type, :log_tag, :log_message, :log_timestamp, :log_thread_id)';
  
  // Create timer for periodic flushing
  FFlushTimer := TTimer.Create(nil);
  FFlushTimer.Interval := FFlushInterval;
  FFlushTimer.OnTimer := OnFlushTimer;
  FFlushTimer.Enabled := True;
end;

procedure TLoggerProSQLiteAppender.TearDown;
begin
  FIsShuttingDown := True;
  
  // Disable timer
  if Assigned(FFlushTimer) then
    FFlushTimer.Enabled := False;
  
  // Flush any remaining logs
  if FLogBuffer.Count > 0 then
  begin
    try
      FlushBufferToDatabase;
    except
      // Ignore errors during teardown
    end;
  end;
  
  // Clean up resources
  FreeAndNil(FQuery);
  if Assigned(FConnection) then
  begin
    FConnection.Connected := False;
    FreeAndNil(FConnection);
  end;
  
  inherited TearDown;
end;

procedure TLoggerProSQLiteAppender.ConfigureSQLite;
var
  LQuery: TFDQuery;
begin
  // Execute PRAGMA statements to optimize SQLite performance
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FConnection;
    
    // Enable Write-Ahead Logging for better concurrency
    LQuery.SQL.Text := 'PRAGMA journal_mode = WAL';
    LQuery.ExecSQL;
    
    // Balance between safety and performance
    LQuery.SQL.Text := 'PRAGMA synchronous = NORMAL';
    LQuery.ExecSQL;
    
    // Use 10MB of memory for cache
    LQuery.SQL.Text := 'PRAGMA cache_size = -10000';
    LQuery.ExecSQL;
    
    // Store temporary tables in memory
    LQuery.SQL.Text := 'PRAGMA temp_store = MEMORY';
    LQuery.ExecSQL;
    
    // Use memory-mapped I/O (256MB)
    LQuery.SQL.Text := 'PRAGMA mmap_size = 268435456';
    LQuery.ExecSQL;
    
    // Optimize for bulk inserts
    LQuery.SQL.Text := 'PRAGMA locking_mode = NORMAL';
    LQuery.ExecSQL;
    
  finally
    LQuery.Free;
  end;
end;

procedure TLoggerProSQLiteAppender.WriteLog(const ALogItem: TLogItem);
begin
  // Add log to buffer
  FBufferLock.Enter;
  try
    FLogBuffer.Add(ALogItem);
    
    // Check if we need to flush
    if (FLogBuffer.Count >= FBatchSize) or 
       (MilliSecondsBetween(Now, FLastFlushTime) >= FFlushInterval) then
    begin
      FlushBuffer;
    end;
  finally
    FBufferLock.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.InternalWriteLog(const ALogItem: TLogItem);
begin
  // This method is not used in this implementation
  // All writing goes through the buffer mechanism
end;

procedure TLoggerProSQLiteAppender.OnFlushTimer(Sender: TObject);
begin
  if not FIsShuttingDown then
  begin
    FBufferLock.Enter;
    try
      if (FLogBuffer.Count > 0) and 
         (MilliSecondsBetween(Now, FLastFlushTime) >= FFlushInterval) then
      begin
        FlushBuffer;
      end;
      
      // Check if it's time to clean up old logs (check once per day)
      if DaysBetween(Now, FLastCleanupTime) >= 1 then
      begin
        FLastCleanupTime := Now;
        CleanupOldLogs;
      end;
    finally
      FBufferLock.Leave;
    end;
  end;
end;

procedure TLoggerProSQLiteAppender.FlushBuffer;
begin
  if FLogBuffer.Count > 0 then
  begin
    FlushBufferToDatabase;
    FLastFlushTime := Now;
  end;
end;

procedure TLoggerProSQLiteAppender.FlushBufferToDatabase;
var
  LBufferCopy: TArray<TLogItem>;
  LLogItem: TLogItem;
  I: Integer;
begin
  // Create a copy of the buffer to minimize lock time
  FBufferLock.Enter;
  try
    SetLength(LBufferCopy, FLogBuffer.Count);
    for I := 0 to FLogBuffer.Count - 1 do
      LBufferCopy[I] := FLogBuffer[I];
    FLogBuffer.Clear;
  finally
    FBufferLock.Leave;
  end;
  
  // Exit if no logs to process
  if Length(LBufferCopy) = 0 then
    Exit;
  
  // Use transaction for batch insert
  try
    FConnection.StartTransaction;
    try
      for I := 0 to High(LBufferCopy) do
      begin
        LLogItem := LBufferCopy[I];
        
        // Prepare parameters
        FQuery.ParamByName('log_type').AsInteger := Integer(LLogItem.LogType);
        FQuery.ParamByName('log_tag').AsString := LLogItem.LogTag;
        FQuery.ParamByName('log_message').AsString := LLogItem.LogMessage;
        FQuery.ParamByName('log_timestamp').AsDateTime := LLogItem.TimeStamp;
        FQuery.ParamByName('log_thread_id').AsInteger := LLogItem.ThreadID;
        
        // Execute the query
        FQuery.ExecSQL;
      end;
      
      // Commit the transaction
      FConnection.Commit;
    except
      // Rollback on error
      FConnection.Rollback;
      raise;
    end;
  except
    on E: Exception do
    begin
      // In a production environment, you might want to log this error
      // to a fallback appender or handle it differently
      OutputDebugString(PChar('Error writing to SQLite: ' + E.Message));
      raise;
    end;
  end;
  
  // Clean up the log items to prevent memory leaks
  for I := 0 to High(LBufferCopy) do
  begin
    LLogItem := LBufferCopy[I];
    LLogItem.Dispose;
  end;
end;

procedure TLoggerProSQLiteAppender.ForceFlush;
begin
  FBufferLock.Enter;
  try
    if FLogBuffer.Count > 0 then
    begin
      FlushBuffer;
    end;
  finally
    FBufferLock.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.EnsureTableExists;
var
  LQuery: TFDQuery;
begin
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FConnection;
    
    // Create table if it doesn't exist
    LQuery.SQL.Text := 
      'CREATE TABLE IF NOT EXISTS loggerpro_logs (' +
      '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
      '  log_type INTEGER NOT NULL,' +
      '  log_tag TEXT,' +
      '  log_message TEXT NOT NULL,' +
      '  log_timestamp DATETIME NOT NULL,' +
      '  log_thread_id INTEGER NOT NULL' +
      ')';
    LQuery.ExecSQL;
    
    // Create indexes if they don't exist
    LQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_loggerpro_logs_timestamp ON loggerpro_logs(log_timestamp)';
    LQuery.ExecSQL;
    
    LQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_loggerpro_logs_type ON loggerpro_logs(log_type)';
    LQuery.ExecSQL;
    
    LQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_loggerpro_logs_tag ON loggerpro_logs(log_tag)';
    LQuery.ExecSQL;
  finally
    LQuery.Free;
  end;
end;

procedure TLoggerProSQLiteAppender.CleanupOldLogs;
var
  LQuery: TFDQuery;
  LCutoffDate: TDateTime;
begin
  // Only clean up if MaxLogAge is set (> 0)
  if FMaxLogAge <= 0 then
    Exit;
    
  LCutoffDate := IncDay(Now, -FMaxLogAge);
  
  LQuery := TFDQuery.Create(nil);
  try
    LQuery.Connection := FConnection;
    
    // Delete logs older than the cutoff date
    LQuery.SQL.Text := 'DELETE FROM loggerpro_logs WHERE log_timestamp < :cutoff_date';
    LQuery.ParamByName('cutoff_date').AsDateTime := LCutoffDate;
    LQuery.ExecSQL;
    
    // Optimize the database after deletion
    LQuery.SQL.Text := 'VACUUM';
    LQuery.ExecSQL;
  except
    on E: Exception do
    begin
      // Log the error but don't raise it - cleanup failures shouldn't stop logging
      OutputDebugString(PChar('Error cleaning up old logs: ' + E.Message));
    end;
  end;
  LQuery.Free;
end;

end.