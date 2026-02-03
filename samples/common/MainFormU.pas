unit MainFormU;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls;

type
  TMainForm = class(TForm)
    Button1: TButton;
    Button2: TButton;
    Button3: TButton;
    Button4: TButton;
    Button5: TButton;
    Button6: TButton;
    Button7: TButton;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure Button3Click(Sender: TObject);
    procedure Button4Click(Sender: TObject);
    procedure Button5Click(Sender: TObject);
    procedure Button6Click(Sender: TObject);
    procedure Button7Click(Sender: TObject);
  private
  { Private declarations }
  public
  { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

uses
  LoggerProConfig;

{$R *.dfm}

procedure TMainForm.Button1Click(Sender: TObject);
begin
  Log.Debug('This is a debug message with TAG1', 'TAG1');
  Log.Debug('This is a debug message with TAG2', 'TAG2');
  var lLogWithCtx := Log
                        .WithProperty('value1',1)
                        .WithProperty('value2','2')
                        .WithProperty('value3',12.34)
                        .WithProperty('value4',true)
                        .WithProperty('value5', Now);
  //the following logs will contain the context data
  lLogWithCtx.Debug('This is the first DEBUG MESSAGE with context', 'TAG3');
  lLogWithCtx.Debug('This is the second DEBUG MESSAGE with context', 'TAG3');
end;

procedure TMainForm.Button2Click(Sender: TObject);
begin
  Log.Info('This is a info message with TAG1', 'TAG1');
  Log.Info('This is a info message with TAG2', 'TAG2');
end;

procedure TMainForm.Button3Click(Sender: TObject);
begin
  Log.Warn('This is a warning message with TAG1', 'TAG1');
  Log.Warn('This is a warning message with TAG2', 'TAG2');
end;

procedure TMainForm.Button4Click(Sender: TObject);
begin
  Log.Error('This is an error message with TAG1', 'TAG1');
  Log.Error('This is an error message with TAG2', 'TAG2');
end;

procedure TMainForm.Button5Click(Sender: TObject);
var
  lThreadProc: TProc;
begin
  lThreadProc :=
      procedure
      var
        I: Integer;
        lThreadID: string;
      begin
        lThreadID := IntToStr(TThread.CurrentThread.ThreadID);
        for I := 1 to 200 do
        begin
          Log.Debug('log message ' + TimeToStr(now) + ' ThreadID: ' + lThreadID, 'MULTITHREADING');
          Log.Info('log message ' + TimeToStr(now) + ' ThreadID: ' + lThreadID, 'MULTITHREADING');
          Log.Warn('log message ' + TimeToStr(now) + ' ThreadID: ' + lThreadID, 'MULTITHREADING');
          Log.Error('log message ' + TimeToStr(now) + ' ThreadID: ' + lThreadID, 'MULTITHREADING');
          Log.Fatal('log message ' + TimeToStr(now) + ' ThreadID: ' + lThreadID, 'MULTITHREADING');
        end;
      end;
  TThread.CreateAnonymousThread(lThreadProc).Start;
  TThread.CreateAnonymousThread(lThreadProc).Start;
  TThread.CreateAnonymousThread(lThreadProc).Start;
  TThread.CreateAnonymousThread(lThreadProc).Start;
end;

procedure TMainForm.Button6Click(Sender: TObject);
begin
  Log.Fatal('This is an fatal message with TAG1', 'TAG1');
  Log.Fatal('This is an fatal message with TAG2', 'TAG2');
end;

procedure TMainForm.Button7Click(Sender: TObject);
begin
  // 演示 TLoggerProMaskingAppender 的脱敏功能
  // 手机号脱敏：13812345678 -> 138****5678
  Log.Info('User login with phone: 13812345678', 'MASKING');
  Log.Info('Contact phone: 15987654321, backup: 13611112222', 'MASKING');

  // 密码脱敏：password=xxx -> password=***
  Log.Info('Login attempt: username=admin, password=secret123', 'MASKING');
  Log.Info('Request: user=john, pwd=myP@ssw0rd, action=login', 'MASKING');
  Log.Info('Config: passwd=abc123, host=localhost', 'MASKING');
  Log.Info('Password with special chars: password=P@$$w0rd!2024', 'MASKING');

  // 混合敏感信息
  Log.Info('User 13812345678 logged in with password=MySecretPwd', 'MASKING');
end;

end.
