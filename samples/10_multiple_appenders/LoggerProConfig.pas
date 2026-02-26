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
  // LoggerPro 2.0 - Builder API with MaskingAppender (Recommended)
  // ============================================================================
  // This sample demonstrates:
  //   - Multiple appenders (File, Console, OutputDebugString)
  //   - TLoggerProMaskingAppender decorator for sensitive data masking
  //   - Conditional log level based on DEBUG/RELEASE build
  //   - WithDefaultLogLevel to set minimum level for all appenders
  //
  // The MaskingAppender wraps other appenders and masks:
  //   - Chinese mobile phone numbers: 13812345678 -> 138****5678
  //   - Password values: password=secret123 -> password=***
  //
  _Log := LoggerProBuilder
    .WithDefaultLogLevel(LOG_LEVEL)
    .WriteToAppender(
      TLoggerProMaskingAppender.Create(
        TLoggerProFileAppender.Create
      )
    )
    .WriteToAppender(
      TLoggerProMaskingAppender.Create(
        TLoggerProConsoleAppender.Create
      )
    )
    .WriteToAppender(
      TLoggerProMaskingAppender.Create(
        TLoggerProOutputDebugStringAppender.Create
      )
    )
    .Build;

  // ============================================================================
  // LoggerPro 1.x - Legacy API (Still supported but deprecated)
  // ============================================================================
  // _Log := BuildLogWriter([
  //   TLoggerProMaskingAppender.Create(TLoggerProFileAppender.Create),
  //   TLoggerProMaskingAppender.Create(TLoggerProConsoleAppender.Create),
  //   TLoggerProMaskingAppender.Create(TLoggerProOutputDebugStringAppender.Create)
  // ], nil, LOG_LEVEL);
end;

initialization

SetupLogger;

end.
