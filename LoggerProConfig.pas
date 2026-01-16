unit LoggerProConfig;

interface

uses
  LoggerPro;

///<summary>global function pointer tha returns a DB Logger instance</summary>
var
  Log: function: ILogWriter;

implementation

uses
  System.SysUtils,
  System.Classes,
  LoggerPro.FileAppender,
  LoggerPro.Builder,
  Data.DB,
  System.IOUtils,
  System.NetEncoding,
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
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  LoggerPro.Renderers,
  LoggerPro.SQLiteAppender;

var
  _Log: ILogWriter;
  _FallbackLog: ILogWriter;

const
  FailedDBWriteTag = 'FailedDBWrite';

function GetFallBackLogger: ILogWriter;
begin
  if _FallbackLog = nil then
  begin
    _FallbackLog := LoggerProBuilder
      .WriteToAppender(TLoggerProSimpleFileAppender.Create(10, 2048, 'logs'))
      .Build;
  end;
  Result := _FallbackLog;
end;

procedure OnSQLiteAppenderError(const Sender: TObject; const LogItem: TLogItem; const DBError: Exception);
var
  lIntf: ILogItemRenderer;
begin
  lIntf := GetDefaultLogItemRenderer();
  GetFallBackLogger.Error('SQLiteAppender Is Failing: %s %s', [DBError.ClassName, DBError.Message], FailedDBWriteTag);
  if Assigned(LogItem) then
    GetFallBackLogger.Error(lIntf.RenderLogItem(LogItem), FailedDBWriteTag);
end;

function GetLogger: ILogWriter;
const
  LOG_DB_PATH = 'logs\loggerpro.db';
begin
  if _Log = nil then
  begin
    GetFallBackLogger.Info('Initializing SQLite appender', FailedDBWriteTag);

    _Log := LoggerProBuilder
      .WriteToAppender(TLoggerProSQLiteAppender.Create(
        LOG_DB_PATH,
        100,
        500,
        OnSQLiteAppenderError))
      .Build;
  end;
  Result := _Log;
end;

initialization

Log := GetLogger;

finalization

_Log := nil;
_FallbackLog := nil;

end.
