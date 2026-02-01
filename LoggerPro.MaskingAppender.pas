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
  System.SysUtils, System.RegularExpressions, LoggerPro, LoggerPro.Proxy;

type
  TLoggerProMaskingAppender = class(TLoggerProAppenderBase, ILogAppender, ILogAppenderProxy)
  private
    FAppender: ILogAppender;
    FPhoneRegex: TRegex;
    FPasswordRegex: TRegex;
    function GetInternalAppender: ILogAppender;
  protected
    function MaskMessage(const aMessage: string): string;
  public
    constructor Create(aAppender: ILogAppender); reintroduce;
    destructor Destroy; override;
    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const aLogItem: TLogItem); override;
    property InternalAppender: ILogAppender read GetInternalAppender;
  end;

implementation

{ TLoggerProMaskingAppender }

constructor TLoggerProMaskingAppender.Create(aAppender: ILogAppender);
begin
  inherited Create;
  FAppender := aAppender;
  FPhoneRegex := TRegex.Create('(^|[^\d])(1[3-9]\d{2})\d{4}(\d{4})([^\d]|$)');
  FPasswordRegex := TRegex.Create('(password\s*[:=]\s*)([^\s;,&]+)', [roIgnoreCase]);
end;

destructor TLoggerProMaskingAppender.Destroy;
begin
  inherited;
end;

function TLoggerProMaskingAppender.GetInternalAppender: ILogAppender;
begin
  Result := FAppender;
end;

function TLoggerProMaskingAppender.MaskMessage(const aMessage: string): string;
begin
  Result := aMessage;
  Result := FPhoneRegex.Replace(Result, '$1$2****$3$4');
  Result := FPasswordRegex.Replace(Result, '$1****');
end;

procedure TLoggerProMaskingAppender.Setup;
begin
  FAppender.Setup;
end;

procedure TLoggerProMaskingAppender.TearDown;
begin
  FAppender.TearDown;
end;

procedure TLoggerProMaskingAppender.WriteLog(const aLogItem: TLogItem);
var
  LMaskedLogItem: TLogItem;
begin
  LMaskedLogItem := TLogItem.Create(
    aLogItem.LogType,
    MaskMessage(aLogItem.LogMessage),
    aLogItem.LogTag,
    aLogItem.TimeStamp,
    aLogItem.ThreadID,
    aLogItem.Context
  );
  try
    FAppender.WriteLog(LMaskedLogItem);
  finally
    LMaskedLogItem.Free;
  end;
end;

end.
