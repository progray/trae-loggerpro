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
  //   - TLoggerProMaskingAppender decorator for sensitive data masking
  //
  // TLoggerProMaskingAppender 使用说明：
  //   - 自动脱敏 11 位中国手机号（如 138****5678）
  //   - 自动脱敏 password=xxx 格式的密码字段
  //   - 正则表达式在构造函数中预编译，确保高并发性能
  //
  _Log := LoggerProBuilder
    .WithDefaultLogLevel(LOG_LEVEL)
    .WriteToAppender(
      // 使用 MaskingAppender 包装 FileAppender，实现日志脱敏
      TLoggerProMaskingAppender.Create(TLoggerProFileAppender.Create)
    )
    .WriteToAppender(
      // 使用 MaskingAppender 包装 ConsoleAppender
      TLoggerProMaskingAppender.Create(TLoggerProConsoleAppender.Create)
    )
    .WriteToAppender(
      // OutputDebugString 也可以选择是否使用脱敏
      TLoggerProOutputDebugStringAppender.Create
    )
    .Build;

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
