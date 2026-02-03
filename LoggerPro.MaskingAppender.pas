// *************************************************************************** }
//
// LoggerPro
//
// Copyright (c) 2010-2026 Daniele Teti
//
// https://github.com/danieleteti/loggerpro
//
// ***************************************************************************
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ***************************************************************************

unit LoggerPro.MaskingAppender;

interface

uses
  System.SysUtils,
  System.RegularExpressions,
  LoggerPro;

type
  TLoggerProMaskingAppender = class(TLoggerProAppenderBase, ILogAppender)
  private
    FInternalAppender: ILogAppender;
    FPhoneRegex: TRegEx;
    FPasswordRegex: TRegEx;
    FPhoneMask: string;
    FPasswordMask: string;
    function MaskLogMessage(const AMessage: string): string;
  public
    constructor Create(AInternalAppender: ILogAppender;
      const APhoneMask: string = '****'; const APasswordMask: string = '***'); reintroduce;
    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const aLogItem: TLogItem); override;
    property InternalAppender: ILogAppender read FInternalAppender;
  end;

implementation

{ TLoggerProMaskingAppender }

constructor TLoggerProMaskingAppender.Create(AInternalAppender: ILogAppender;
  const APhoneMask: string; const APasswordMask: string);
begin
  inherited Create;
  FInternalAppender := AInternalAppender;
  FPhoneMask := APhoneMask;
  FPasswordMask := APasswordMask;

  // 预编译正则表达式，避免在高并发日志下产生性能瓶颈
  // 匹配 11 位中国手机号：中间 4 位脱敏
  // 格式：1[3-9]xx xxxx xxxx，保留前3位和后4位
  FPhoneRegex := TRegEx.Create('(1[3-9]\d)(\d{4})(\d{4})',
    [roCompiled, roIgnoreCase, roMultiLine]);

  // 匹配 password=xxx 或 password:xxx 格式，不区分大小写
  // 支持 password, pwd, passwd 等变体
  FPasswordRegex := TRegEx.Create('((?:password|pwd|passwd)\s*[=:]\s*)([^\s&;,]+)',
    [roCompiled, roIgnoreCase, roMultiLine]);
end;

function TLoggerProMaskingAppender.MaskLogMessage(const AMessage: string): string;
begin
  Result := AMessage;

  // 脱敏手机号：13812345678 -> 138****5678
  Result := FPhoneRegex.Replace(Result, '$1' + FPhoneMask + '$3');

  // 脱敏密码字段：password=secret123 -> password=***
  Result := FPasswordRegex.Replace(Result, '$1' + FPasswordMask);
end;

procedure TLoggerProMaskingAppender.Setup;
begin
  FInternalAppender.Setup;
end;

procedure TLoggerProMaskingAppender.TearDown;
begin
  FInternalAppender.TearDown;
end;

procedure TLoggerProMaskingAppender.WriteLog(const aLogItem: TLogItem);
var
  LMaskedLogItem: TLogItem;
  LMaskedMessage: string;
begin
  // 对日志消息进行脱敏处理
  LMaskedMessage := MaskLogMessage(aLogItem.LogMessage);

  // 如果消息没有变化，直接传递原始日志项
  if LMaskedMessage = aLogItem.LogMessage then
  begin
    FInternalAppender.WriteLog(aLogItem);
  end
  else
  begin
    // 创建新的日志项，包含脱敏后的消息
    LMaskedLogItem := TLogItem.Create(
      aLogItem.LogType,
      LMaskedMessage,
      aLogItem.LogTag,
      aLogItem.TimeStamp,
      aLogItem.ThreadID,
      aLogItem.Context
    );
    try
      FInternalAppender.WriteLog(LMaskedLogItem);
    finally
      LMaskedLogItem.Free;
    end;
  end;
end;

end.
