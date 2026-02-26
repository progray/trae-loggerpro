unit LoggerPro.MaskingAppender;

interface

uses
  System.SysUtils, System.RegularExpressions, LoggerPro;

type
  TLoggerProMaskingAppender = class(TLoggerProAppenderBase, ILogAppender)
  private
    FAppender: ILogAppender;
    FPhoneRegex: TRegEx;
    FPasswordRegex: TRegEx;
    function MaskMessage(const aMessage: string): string;
  protected
    procedure Setup; override;
    procedure TearDown; override;
    procedure WriteLog(const aLogItem: TLogItem); override;
  public
    constructor Create(aAppender: ILogAppender); reintroduce;
    destructor Destroy; override;
  end;

implementation

{ TLoggerProMaskingAppender }

constructor TLoggerProMaskingAppender.Create(aAppender: ILogAppender);
begin
  inherited Create;
  FAppender := aAppender;
  FPhoneRegex := TRegEx.Create('(\d{3})\d{4}(\d{4})', [roCompiled]);
  FPasswordRegex := TRegEx.Create('(password\s*[:=]\s*)([^\s;,&]+)', [roIgnoreCase, roCompiled]);
end;

destructor TLoggerProMaskingAppender.Destroy;
begin
  FAppender := nil;
  inherited;
end;

function TLoggerProMaskingAppender.MaskMessage(const aMessage: string): string;
begin
  Result := aMessage;
  Result := FPhoneRegex.Replace(Result, '$1****$2');
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
  lMaskedMessage: string;
  lLogItem: TLogItem;
begin
  lMaskedMessage := MaskMessage(aLogItem.LogMessage);
  lLogItem := TLogItem.Create(aLogItem.LogType, lMaskedMessage, aLogItem.LogTag,
    aLogItem.TimeStamp, aLogItem.ThreadID, aLogItem.Context);
  try
    FAppender.WriteLog(lLogItem);
  finally
    lLogItem.Free;
  end;
end;

end.
