unit LoggerProConfig;

interface

uses
  LoggerPro;

function Log: ILogWriter;

implementation

uses
  LoggerPro.FileAppender,
  LoggerPro.ConsoleAppender,
  LoggerPro.OutputDebugStringAppender,
  LoggerPro.MaskingAppender,
  LoggerPro.Builder;

var
  _Log: ILogWriter;

function Log: ILogWriter;
begin
  Result := _Log;
end;

procedure SetupLogger;
const
{$IFDEF DEBUG}
  LOG_LEVEL = TLogType.Debug;
{$ELSE}
  LOG_LEVEL = TLogType.Warning;
{$ENDIF}
begin
  // ============================================================================
  // LoggerPro 2.0 - Builder API (Recommended)
  // ============================================================================
  // This sample demonstrates:
  //   - Multiple appenders (File, Console, OutputDebugString)
  //   - Conditional log level based on DEBUG/RELEASE build
  //   - WithDefaultLogLevel to set minimum level for all appenders
  //   - MaskingAppender to hide sensitive data (phone numbers and passwords)
  //
  _Log := LoggerProBuilder
    .WithDefaultLogLevel(LOG_LEVEL)
    .WriteToFile.Done
    .WriteToConsole.Done
    .WriteToOutputDebugString.Done
    .Build;

  // ============================================================================
  // LoggerPro with MaskingAppender Example
  // ============================================================================
  // Example of using MaskingAppender to wrap another appender:
  // var
  //   FileAppender: ILogAppender;
  // begin
  //   FileAppender := TLoggerProFileAppender.Create;
  //   _Log := LoggerProBuilder
  //     .WithDefaultLogLevel(LOG_LEVEL)
  //     .WriteToAppender(TLoggerProMaskingAppender.Create(FileAppender))
  //     .Build;
  // end;

  // ============================================================================
  // LoggerPro 1.x - Legacy API (Still supported but deprecated)
  // ============================================================================
  // _Log := BuildLogWriter([
  //   TLoggerProFileAppender.Create,
  //   TLoggerProConsoleAppender.Create,
  //   TLoggerProOutputDebugStringAppender.Create
  // ], nil, LOG_LEVEL);
end;

initialization

SetupLogger;

end.
