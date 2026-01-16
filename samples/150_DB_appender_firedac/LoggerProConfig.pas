unit LoggerProConfig;

// instantiate and call the Logging appender that writes to the Logging database

interface

uses
  LoggerPro,
  System.Generics.Collections,
  FireDAC.Comp.Client,
  Vcl.ExtCtrls,
  System.Classes;

type
  TLoggerProSQLiteAppenderFireDAC = class(TLoggerProAppenderBase)
  strict private
    FConnection: TFDConnection;
    FSQLiteDBPath: string;
    FBuffer: TThreadList<TLogItem>;
    FLastFlushTime: TDateTime;
    FMaxBufferSize: Integer;
    FFlushInterval: Integer;
    FLogTableName: string;
    FFlushTimer: TTimer;
    FMaxDatabaseSize: Int64;
    FCleanupPercentage: Integer;
    procedure FlushBuffer;
    procedure EnsureTableExists;
    procedure CreateTableIfNotExists;
    procedure ConfigureSQLiteOptions;
    procedure FlushTimerHandler(Sender: TObject);
    procedure CheckAndCleanupDatabase;
    function GetDatabaseSize: Int64;
    procedure CleanupByPriority;
  public
    procedure WriteLog(const aLogItem: TLogItem); override;
  public
    constructor Create(const ASQLiteDBPath: string; const ALogTableName: string = 'logs'); reintroduce; virtual;
    destructor Destroy; override;
    procedure Setup; override;
    procedure TearDown; override;
  end;

///<summary>global function pointer tha returns a DB Logger instance</summary>
var
  Log: function: ILogWriter;

implementation

uses
  System.SysUtils,
  LoggerPro.DBAppender.FireDAC,
  LoggerPro.FileAppender,
  LoggerPro.Builder,
  Data.DB,
  System.IOUtils,
  System.NetEncoding,
  System.DateUtils,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.Phys,
  FireDAC.VCLUI.Wait,
  FDConnectionConfigU,
  LoggerPro.Renderers;

var
  _Log: ILogWriter;
  _FallbackLog: ILogWriter;

const
  FailedDBWriteTag = 'FailedDBWrite';


function GetFallBackLogger: ILogWriter;
begin
  if _FallbackLog = nil then
  begin
    // BuildLogWriter is the classic way to create a log writer.
    // The modern and recommended approach is to use LoggerProBuilder.
    //_FallbackLog := BuildLogWriter([
    //  TLoggerProSimpleFileAppender.Create(10, 2048, 'logs')
    //]);
    _FallbackLog := LoggerProBuilder
      .WriteToAppender(TLoggerProSimpleFileAppender.Create(10, 2048, 'logs'))
      .Build;
  end;
  Result := _FallbackLog;
end;

function GetLogger: ILogWriter;
begin

  if _Log = nil then
  begin
    GetFallBackLogger.Info('Initializing SQLite db appender', FailedDBWriteTag);
    _Log := LoggerProBuilder
      .WriteToAppender(TLoggerProSQLiteAppenderFireDAC.Create('logs.db'))
      .Build;
  end;
  Result := _Log;
end;

{ TLoggerProSQLiteAppenderFireDAC }

constructor TLoggerProSQLiteAppenderFireDAC.Create(const ASQLiteDBPath: string; const ALogTableName: string; const AMaxDatabaseSizeMB: Integer = 500);
begin
  inherited Create;
  FSQLiteDBPath := ASQLiteDBPath;
  FLogTableName := ALogTableName;
  FMaxBufferSize := 100;
  FFlushInterval := 500;
  FBuffer := TThreadList<TLogItem>.Create;
  FLastFlushTime := Now;
  FMaxDatabaseSize := AMaxDatabaseSizeMB * 1024 * 1024;
  FCleanupPercentage := 20;
  FFlushTimer := TTimer.Create(nil);
  FFlushTimer.Interval := FFlushInterval;
  FFlushTimer.OnTimer := FlushTimerHandler;
  FFlushTimer.Enabled := False;
end;

destructor TLoggerProSQLiteAppenderFireDAC.Destroy;
begin
  FFlushTimer.Free;
  FlushBuffer;
  FBuffer.Free;
  FConnection.Free;
  inherited;
end;

procedure TLoggerProSQLiteAppenderFireDAC.Setup;
begin
  inherited;
  FConnection := TFDConnection.Create(nil);
  FConnection.DriverName := 'SQLite';
  FConnection.Params.Add('Database=' + FSQLiteDBPath);
  FConnection.LoginPrompt := False;
  try
    FConnection.Connected := True;
    ConfigureSQLiteOptions;
    EnsureTableExists;
    FFlushTimer.Enabled := True;
  except
    on E: Exception do
    begin
      GetFallBackLogger.Error('Failed to setup SQLite appender: ' + E.Message, FailedDBWriteTag);
      raise;
    end;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.TearDown;
begin
  FFlushTimer.Enabled := False;
  FlushBuffer;
  FConnection.Connected := False;
  inherited;
end;

procedure TLoggerProSQLiteAppenderFireDAC.ConfigureSQLiteOptions;
begin
  FConnection.ExecSQL('PRAGMA journal_mode = WAL');
  FConnection.ExecSQL('PRAGMA synchronous = NORMAL');
end;

procedure TLoggerProSQLiteAppenderFireDAC.EnsureTableExists;
begin
  CreateTableIfNotExists;
end;

procedure TLoggerProSQLiteAppenderFireDAC.CreateTableIfNotExists;
begin
  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS ' + FLogTableName + ' (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'log_type INTEGER, ' +
    'log_tag TEXT, ' +
    'log_message TEXT, ' +
    'log_timestamp TIMESTAMP, ' +
    'log_thread_id INTEGER' +
    ')');
end;

procedure TLoggerProSQLiteAppenderFireDAC.FlushTimerHandler(Sender: TObject);
begin
  FlushBuffer;
  CheckAndCleanupDatabase;
end;

procedure TLoggerProSQLiteAppenderFireDAC.CheckAndCleanupDatabase;
var
  LDBSize: Int64;
begin
  LDBSize := GetDatabaseSize;
  if LDBSize > FMaxDatabaseSize then
  begin
    GetFallBackLogger.Info(Format('Database size %d MB exceeds limit %d MB, starting cleanup', 
      [LDBSize div (1024*1024), FMaxDatabaseSize div (1024*1024)]), 'DB_CLEANUP');
    CleanupByPriority;
  end;
end;

function TLoggerProSQLiteAppenderFireDAC.GetDatabaseSize: Int64;
var
  LFileInfo: TSearchRec;
begin
  if FindFirst(FSQLiteDBPath, faAnyFile, LFileInfo) = 0 then
  begin
    Result := LFileInfo.Size;
    FindClose(LFileInfo);
  end
  else
    Result := 0;
end;

procedure TLoggerProSQLiteAppenderFireDAC.CleanupByPriority;
var
  LDeleteCount: Integer;
  LTryLogType: TLogType;
  LSQL: string;
begin
  FConnection.StartTransaction;
  try
    LDeleteCount := 0;
    for LTryLogType := TLogType.Debug to TLogType.Fatal do
    begin
      LSQL := Format('DELETE FROM %s WHERE log_type = %d ORDER BY log_timestamp ASC LIMIT %d', 
        [FLogTableName, Integer(LTryLogType), FCleanupPercentage * 100]);
      FConnection.ExecSQL(LSQL);
      LDeleteCount := LDeleteCount + FConnection.RowsAffected;
      if GetDatabaseSize < (FMaxDatabaseSize * 9) div 10 then
        Break;
    end;
    FConnection.ExecSQL('VACUUM');
    FConnection.Commit;
    GetFallBackLogger.Info(Format('Cleanup completed, deleted %d records', [LDeleteCount]), 'DB_CLEANUP');
  except
    FConnection.Rollback;
    raise;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.WriteLog(const aLogItem: TLogItem);
var
  LList: TList<TLogItem>;
begin
  if not Assigned(FConnection) or not FConnection.Connected then
  begin
    GetFallBackLogger.Error('SQLite connection is not available', FailedDBWriteTag);
    Exit;
  end;

  LList := FBuffer.LockList;
  try
    LList.Add(aLogItem.Clone);
    if LList.Count >= FMaxBufferSize then
    begin
      FlushBuffer;
    end;
  finally
    FBuffer.UnlockList;
  end;
end;

procedure TLoggerProSQLiteAppenderFireDAC.FlushBuffer;
var
  LList: TList<TLogItem>;
  LBatch: TList<TLogItem>;
  LLogItem: TLogItem;
  I: Integer;
begin
  LList := FBuffer.LockList;
  try
    if LList.Count = 0 then Exit;

    LBatch := TList<TLogItem>.Create;
    try
      LBatch.AddRange(LList);
      LList.Clear;
    finally
      FBuffer.UnlockList;
    end;

    try
      FConnection.StartTransaction;
      try
        for I := 0 to LBatch.Count - 1 do
        begin
          LLogItem := LBatch[I];
          try
            FConnection.ExecSQL(
              'INSERT INTO ' + FLogTableName + ' (log_type, log_tag, log_message, log_timestamp, log_thread_id) VALUES (?, ?, ?, ?, ?)',
              [Integer(LLogItem.LogType), LLogItem.LogTag, LLogItem.LogMessage, LLogItem.TimeStamp, LLogItem.ThreadID]);
          finally
            LLogItem.Free;
          end;
        end;
        FConnection.Commit;
      except
        FConnection.Rollback;
        raise;
      end;
    except
      on E: Exception do
      begin
        GetFallBackLogger.Error('Failed to flush buffer: ' + E.Message, FailedDBWriteTag);
        FBuffer.LockList;
        try
          LList.AddRange(LBatch);
        finally
          FBuffer.UnlockList;
        end;
      end;
    end;
  finally
    LBatch.Free;
  end;
end;

initialization

Log := GetLogger;

finalization

_Log := nil;
_FallbackLog := nil;

end.
