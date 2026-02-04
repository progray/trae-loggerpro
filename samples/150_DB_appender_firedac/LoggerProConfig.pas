unit LoggerProConfig;

interface

uses
  LoggerPro;

var
  Log: function: ILogWriter;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  LoggerPro.SQLiteAppender.FireDAC,
  LoggerPro.FileAppender,
  LoggerPro.Builder,
  LoggerPro.Renderers;

var
  _Log: ILogWriter;
  _FallbackLog: ILogWriter;

const
  FailedDBWriteTag = 'FailedDBWrite';
  SQLiteDBName = 'application_logs.db';
  LogBackupFolder = 'logs';

function GetFallBackLogger: ILogWriter;
begin
  if _FallbackLog = nil then
  begin
    if not TDirectory.Exists(LogBackupFolder) then
      TDirectory.CreateDirectory(LogBackupFolder);
      
    _FallbackLog := LoggerProBuilder
      .WriteToAppender(TLoggerProSimpleFileAppender.Create(10, 2048, LogBackupFolder))
      .Build;
  end;
  Result := _FallbackLog;
end;

function GetLogger: ILogWriter;
var
  LDBPath: string;
  LSQLiteAppender: TLoggerProSQLiteAppenderFireDAC;
begin
  if _Log = nil then
  begin
    GetFallBackLogger.Info('Initializing SQLite appender', FailedDBWriteTag);

    LDBPath := TPath.Combine(TPath.GetDocumentsPath, SQLiteDBName);
    
    LSQLiteAppender := TLoggerProSQLiteAppenderFireDAC.Create(
      LDBPath,                    // Database path
      100,                        // Batch size: flush after 100 logs
      500,                        // Flush interval: 500ms
      30,                         // Cleanup days: keep 30 days of logs
      True,                       // Enable auto cleanup
      True,                       // Enable WAL mode
      // OnSQLiteWriteError handler
      procedure(const Sender: TObject; const LogItem: TLogItem; const DBError: Exception; var RetryCount: Integer)
      var
        LIntf: ILogItemRenderer;
      begin
        LIntf := GetDefaultLogItemRenderer();
        GetFallBackLogger.Error('SQLiteAppender Write Error (Retry: %d): %s - %s', 
          [RetryCount, DBError.ClassName, DBError.Message], FailedDBWriteTag);
        if LogItem <> nil then
          GetFallBackLogger.Error(LIntf.RenderLogItem(LogItem), FailedDBWriteTag);
      end,
      // OnSQLiteCleanup handler
      procedure(const Sender: TObject; const DeletedRecords: Integer)
      begin
        GetFallBackLogger.Info(Format('SQLiteAppender cleanup completed. Deleted %d old log records.', 
          [DeletedRecords]), FailedDBWriteTag);
      end
    );

    _Log := LoggerProBuilder
      .WriteToAppender(LSQLiteAppender)
      .Build;
      
    GetFallBackLogger.Info(Format('SQLite appender initialized. Database: %s', [LDBPath]), FailedDBWriteTag);
  end;
  Result := _Log;
end;

initialization
  Log := GetLogger;

finalization
  _Log := nil;
  _FallbackLog := nil;

end.
