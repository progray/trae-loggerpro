unit LoggerProConfig;

// instantiate and call the Logging appender that writes to the Logging database

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
  LoggerPro.DBAppender.FireDAC,
  LoggerPro.SQLiteAppender,
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
    GetFallBackLogger.Info('Initializing SQLite appender', FailedDBWriteTag);

    _Log := LoggerProBuilder
      .WriteToAppender(TLoggerProSQLiteAppender.Create(
        function: TCustomConnection
        begin
          Result := TFDConnection.Create(nil);
          Result.LoginPrompt := False;
          TFDConnection(Result).ConnectionDefName := CON_DEF_NAME;
          TFDConnection(Result).DriverName := 'SQLite';
        end,
        procedure(const Sender: TObject; const LogItem: TLogItem; const DBError: Exception; var RetryCount: Integer)
        var
          lIntf: ILogItemRenderer;
        begin
          lIntf := GetDefaultLogItemRenderer();
          GetFallBackLogger.Error('SQLiteAppender Is Failing (%d): %s %s', [RetryCount, DBError.ClassName, DBError.Message], FailedDBWriteTag);
          GetFallBackLogger.Error(lIntf.RenderLogItem(LogItem), FailedDBWriteTag);
        end,
        100,
        500,
        'logs',
        500,
        7))
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
