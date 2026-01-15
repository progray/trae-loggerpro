program multiple_appenders;

uses
  Vcl.Forms,
  LoggerProConfig in 'LoggerProConfig.pas',
  LoggerPro.MaskingAppender in '..\..\LoggerPro.MaskingAppender.pas',
  MainFormU in '..\common\MainFormU.pas' {MainForm};

{$R *.res}

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
