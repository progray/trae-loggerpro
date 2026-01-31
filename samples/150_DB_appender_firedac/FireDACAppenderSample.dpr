program FireDACAppenderSample;

uses
  Vcl.Forms,
  FireDACAppenderFormU in 'FireDACAppenderFormU.pas' {MainForm},
  LoggerProConfig in 'LoggerProConfig.pas',
  FDConnectionConfigU in 'FDConnectionConfigU.pas',
  SQLiteDBInit in 'SQLiteDBInit.pas';

//LoggerPro.RESTAppender in '..\..\LoggerPro.RESTAppender.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  CreateSqliteOptimizedConnDef(False);
  InitializeSQLiteDatabase;  // Initialize SQLite database and tables
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
