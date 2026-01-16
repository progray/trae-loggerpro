unit LoggerPro.SQLiteAppender.FireDAC;

interface

uses
  System.Classes,
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.UI.Intf,
  FireDAC.Phys.Intf,
  FireDAC.Stan.Def,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Async,
  FireDAC.Phys,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.VCLUI.Wait,
  FireDAC.Comp.Client,
  FireDAC.Stan.Param,
  FireDAC.DatS,
  FireDAC.DApt.Intf,
  FireDAC.DApt,
  FireDAC.Comp.DataSet,
  LoggerPro;

type
  TLoggerProSQLiteAppender = class(TLoggerProAppenderBase)
  private
    FConnection: TFDConnection;
    FBuffer: TQueue<TLogItem>;
    FBufferLock: TCriticalSection;
    FBufferSize: Integer;
    FFlushInterval: Cardinal;
    FLastFlushTime: Cardinal;
    FInsertCommand: TFDCommand;
    procedure ConfigureSQLite;
    procedure EnsureTableExists;
    procedure FlushBuffer;
    procedure AddToBuffer(const ALogItem: TLogItem);
  protected
    procedure WriteLog(const ALogItem: TLogItem); override;
    procedure Setup; override;
    procedure TearDown; override;
  public
    constructor Create(const ADatabasePath: string; ABufferSize: Integer = 100; AFlushInterval: Cardinal = 500); reintroduce;
    destructor Destroy; override;
  end;

implementation

uses
  System.IOUtils;

constructor TLoggerProSQLiteAppender.Create(const ADatabasePath: string; ABufferSize: Integer; AFlushInterval: Cardinal);
begin
  inherited Create;
  FConnection := TFDConnection.Create(nil);
  FConnection.DriverName := 'SQLite';
  FConnection.Params.Database := ADatabasePath;
  FBuffer := TQueue<TLogItem>.Create;
  FBufferLock := TCriticalSection.Create;
  FBufferSize := ABufferSize;
  FFlushInterval := AFlushInterval;
  FLastFlushTime := TThread.GetTickCount;
end;

destructor TLoggerProSQLiteAppender.Destroy;
begin
  FlushBuffer;
  FInsertCommand.Free;
  FConnection.Free;
  FBuffer.Free;
  FBufferLock.Free;
  inherited;
end;

procedure TLoggerProSQLiteAppender.Setup;
begin
  inherited;
  ConfigureSQLite;
  EnsureTableExists;
  FConnection.Connected := True;
  FInsertCommand := TFDCommand.Create(nil);
  FInsertCommand.Connection := FConnection;
  FInsertCommand.CommandText.Text :=
    'INSERT INTO log_messages (log_level, log_message, log_tag, log_timestamp, log_threadid) ' +
    'VALUES (:log_level, :log_message, :log_tag, :log_timestamp, :log_threadid)';
end;

procedure TLoggerProSQLiteAppender.TearDown;
begin
  FlushBuffer;
  FConnection.Connected := False;
  inherited;
end;

procedure TLoggerProSQLiteAppender.ConfigureSQLite;
var
  lParams: TPhysSQLiteConnectionParams;
begin
  lParams := TPhysSQLiteConnectionParams.Create(FConnection.Params);
  try
    lParams.WALMode := walWAL;
    lParams.Synchronous := smNormal;
    lParams.ForeignKeys := True;
    lParams.PageSize := 4096;
    lParams.CacheSize := 2000;
  finally
    lParams.Free;
  end;
end;

procedure TLoggerProSQLiteAppender.EnsureTableExists;
begin
  if not FConnection.Connected then
    FConnection.Connected := True;

  FConnection.ExecSQL(
    'CREATE TABLE IF NOT EXISTS log_messages (' +
    'id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    'log_level INTEGER, ' +
    'log_message TEXT, ' +
    'log_tag TEXT, ' +
    'log_timestamp TEXT, ' +
    'log_threadid INTEGER)');
end;

procedure TLoggerProSQLiteAppender.WriteLog(const ALogItem: TLogItem);
begin
  AddToBuffer(ALogItem);

  if (FBuffer.Count >= FBufferSize) or
     (GetTickCount - FLastFlushTime >= FFlushInterval) then
  begin
    FlushBuffer;
  end;
end;

procedure TLoggerProSQLiteAppender.AddToBuffer(const ALogItem: TLogItem);
begin
  FBufferLock.Enter;
  try
    FBuffer.Enqueue(ALogItem);
  finally
    FBufferLock.Leave;
  end;
end;

procedure TLoggerProSQLiteAppender.FlushBuffer;
var
  lLogItem: TLogItem;
  lBatchSize: Integer;
begin
  if FBuffer.Count = 0 then
    Exit;

  FBufferLock.Enter;
  try
    lBatchSize := FBuffer.Count;
    if lBatchSize = 0 then
      Exit;

    FConnection.StartTransaction;
    try
      while FBuffer.Count > 0 do
      begin
        lLogItem := FBuffer.Dequeue;

        FInsertCommand.ParamByName('log_level').AsInteger := Ord(lLogItem.LogLevel);
        FInsertCommand.ParamByName('log_message').AsString := lLogItem.LogMessage;
        FInsertCommand.ParamByName('log_tag').AsString := lLogItem.LogTag;
        FInsertCommand.ParamByName('log_timestamp').AsString := DateTimeToStr(lLogItem.LogTimestamp);
        FInsertCommand.ParamByName('log_threadid').AsInteger := lLogItem.ThreadID;

        FInsertCommand.Execute;
      end;
      FConnection.Commit;
    except
      FConnection.Rollback;
      raise;
    end;

    FLastFlushTime := GetTickCount;
  finally
    FBufferLock.Leave;
  end;
end;

end.
