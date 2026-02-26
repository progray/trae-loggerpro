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
  LoggerPro,
  System.Classes,
  System.SysUtils,
  System.RegularExpressions;

type
  { @abstract(Masking appender that sanitizes sensitive data in log messages)
    This is a decorator appender that wraps another appender and applies
    masking rules to log messages before forwarding them.
    
    Currently supports:
    - Chinese mobile phone numbers: masks middle 4 digits (e.g., 138****5678)
    - Password values: masks values after 'password=' (case-insensitive)
    
    The regular expressions are pre-compiled in the constructor for performance.
  }
  TLoggerProMaskingAppender = class(TLoggerProAppenderBase)
  private
    FInnerAppender: ILogAppender;
    FPhoneRegex: TRegEx;
    FPasswordRegex: TRegEx;
    FPhoneReplacement: string;
    FPasswordReplacement: string;
  protected
    function MaskMessage(const AMessage: string): string; virtual;
  public
    constructor Create(const AInnerAppender: ILogAppender); overload; virtual;
    destructor Destroy; override;
    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const aLogItem: TLogItem); override;
    procedure TryToRestart(var Restarted: Boolean); override;
    property InnerAppender: ILogAppender read FInnerAppender;
  end;

implementation

{ TLoggerProMaskingAppender }

constructor TLoggerProMaskingAppender.Create(const AInnerAppender: ILogAppender);
begin
  inherited Create;
  FInnerAppender := AInnerAppender;
  
  // Pre-compile regex patterns for performance optimization
  // This avoids recompiling regex on every log call in high-concurrency scenarios
  
  // Pattern for Chinese mobile phone numbers: 11 digits starting with 1
  // Captures: (first 3 digits)(middle 4 digits)(last 4 digits)
  // Matches: 13812345678 -> 138****5678
  FPhoneRegex := TRegEx.Create(
    '(1[3-9]\d)(\d{4})(\d{4})',
    [roCompiled, roMultiLine]
  );
  FPhoneReplacement := '$1****$3';
  
  // Pattern for password values: matches 'password=' followed by any value
  // Case-insensitive, supports various formats:
  // - password=secret123
  // - password="my pass"
  // - password='secret'
  // - password: value
  // - &password=xxx&
  // - ?password=xxx&
  // - JSON: "password":"value"
  FPasswordRegex := TRegEx.Create(
    '(password\s*[=:]\s*)([^\s&"'']+|"[^"]*"|''[^'']*'')',
    [roCompiled, roMultiLine, roIgnoreCase]
  );
  FPasswordReplacement := '$1***';
end;

destructor TLoggerProMaskingAppender.Destroy;
begin
  FInnerAppender := nil;
  inherited;
end;

function TLoggerProMaskingAppender.MaskMessage(const AMessage: string): string;
begin
  Result := AMessage;
  
  // Mask Chinese mobile phone numbers
  Result := FPhoneRegex.Replace(Result, FPhoneReplacement);
  
  // Mask password values
  Result := FPasswordRegex.Replace(Result, FPasswordReplacement);
end;

procedure TLoggerProMaskingAppender.Setup;
begin
  if FInnerAppender <> nil then
    FInnerAppender.Setup;
end;

procedure TLoggerProMaskingAppender.TearDown;
begin
  if FInnerAppender <> nil then
    FInnerAppender.TearDown;
end;

procedure TLoggerProMaskingAppender.TryToRestart(var Restarted: Boolean);
begin
  if FInnerAppender <> nil then
    FInnerAppender.TryToRestart(Restarted)
  else
    Restarted := False;
end;

procedure TLoggerProMaskingAppender.WriteLog(const aLogItem: TLogItem);
var
  LMaskedLogItem: TLogItem;
  LMaskedMessage: string;
begin
  if FInnerAppender = nil then
    Exit;
    
  // Apply masking to the log message
  LMaskedMessage := MaskMessage(aLogItem.LogMessage);
  
  // Create a new log item with the masked message
  LMaskedLogItem := TLogItem.Create(
    aLogItem.LogType,
    LMaskedMessage,
    aLogItem.LogTag,
    aLogItem.TimeStamp,
    aLogItem.ThreadID,
    aLogItem.Context
  );
  
  try
    // Forward to the inner appender
    FInnerAppender.WriteLog(LMaskedLogItem);
  finally
    LMaskedLogItem.Free;
  end;
end;

end.
