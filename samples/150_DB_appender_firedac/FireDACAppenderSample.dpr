program FireDACAppenderSample;

uses
  Vcl.Forms,
  FireDACAppenderFormU in 'FireDACAppenderFormU.pas' {MainForm},
  LoggerProConfig in 'LoggerProConfig.pas',
  LoggerPro.SQLiteAppender.FireDAC in 'LoggerPro.SQLiteAppender.FireDAC.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
