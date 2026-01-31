program SQLiteAppenderTest;

{$APPTYPE CONSOLE}

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.DApt,
  FireDAC.Comp.UI,
  FireDAC.Phys.SQLite,
  FireDAC.Phys.SQLiteDef,
  FireDAC.Stan.ExprFuncs,
  FireDAC.UI.Intf,
  FireDAC.VCLUI.Wait,
  FireDAC.Stan.Intf,
  FireDAC.Stan.Option,
  FireDAC.Stan.Error,
  FireDAC.Stan.Pool,
  FireDAC.Stan.Param,
  LoggerPro,
  LoggerProConfig in 'LoggerProConfig.pas',
  FDConnectionConfigU in 'FDConnectionConfigU.pas',
  SQLiteDBInit in 'SQLiteDBInit.pas',
  LoggerPro.SQLiteAppender in 'LoggerPro.SQLiteAppender.pas';

begin
  try
    WriteLn('Initializing SQLite Appender...');
    
    // Initialize database
    InitializeSQLiteDatabase;
    
    // Test basic logging
    WriteLn('Testing basic SQLite logging...');
    SQLiteLog.Debug('This is a debug message', 'TEST');
    SQLiteLog.Info('This is an info message', 'TEST');
    SQLiteLog.Warn('This is a warning message', 'TEST');
    SQLiteLog.Error('This is an error message', 'TEST');
    SQLiteLog.Fatal('This is a fatal message', 'TEST');
    
    // Force flush to ensure all logs are written
    if SQLiteLog is TLoggerProSQLiteAppender then
      TLoggerProSQLiteAppender(SQLiteLog).ForceFlush;
    
    WriteLn('Basic logging test completed.');
    
    // Test multithreaded logging
    WriteLn('Testing multithreaded SQLite logging...');
    
    // Create multiple threads to test concurrent logging
    var LTask1 := TTask.Run(procedure
    var
      I: Integer;
    begin
      for I := 1 to 50 do
      begin
        SQLiteLog.Debug('Thread 1: Debug message %d', [I], 'MULTITHREAD');
        SQLiteLog.Info('Thread 1: Info message %d', [I], 'MULTITHREAD');
        Sleep(1);
      end;
    end);
    
    var LTask2 := TTask.Run(procedure
    var
      I: Integer;
    begin
      for I := 1 to 50 do
      begin
        SQLiteLog.Warn('Thread 2: Warning message %d', [I], 'MULTITHREAD');
        SQLiteLog.Error('Thread 2: Error message %d', [I], 'MULTITHREAD');
        Sleep(1);
      end;
    end);
    
    // Wait for all tasks to complete
    TTask.WaitForAll([LTask1, LTask2]);
    
    // Force flush to ensure all logs are written
    if SQLiteLog is TLoggerProSQLiteAppender then
      TLoggerProSQLiteAppender(SQLiteLog).ForceFlush;
    
    WriteLn('Multithreaded logging test completed.');
    WriteLn('SQLite Appender test completed successfully.');
    
    // Verify logs in database
    WriteLn('Verifying logs in database...');
    var LConnection := TFDConnection.Create(nil);
    try
      LConnection.DriverName := 'SQLite';
      LConnection.Params.Values['Database'] := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'data\loggerpro_sqlite.db');
      LConnection.Connected := True;
      
      var LQuery := TFDQuery.Create(nil);
      try
        LQuery.Connection := LConnection;
        LQuery.SQL.Text := 'SELECT COUNT(*) AS LogCount FROM loggerpro_logs';
        LQuery.Open;
        var LLogCount := LQuery.FieldByName('LogCount').AsInteger;
        WriteLn(Format('Total logs in database: %d', [LLogCount]));
        LQuery.Close;
        
        LQuery.SQL.Text := 'SELECT log_type, COUNT(*) AS TypeCount FROM loggerpro_logs GROUP BY log_type';
        LQuery.Open;
        WriteLn('Logs by type:');
        while not LQuery.Eof do
        begin
          var LLogType := LQuery.FieldByName('log_type').AsInteger;
          var LTypeCount := LQuery.FieldByName('TypeCount').AsInteger;
          var LLogTypeName := '';
          case LLogType of
            0: LLogTypeName := 'Debug';
            1: LLogTypeName := 'Info';
            2: LLogTypeName := 'Warning';
            3: LLogTypeName := 'Error';
            4: LLogTypeName := 'Fatal';
          end;
          WriteLn(Format('  %s: %d', [LLogTypeName, LTypeCount]));
          LQuery.Next;
        end;
        LQuery.Close;
      finally
        LQuery.Free;
      end;
    finally
      LConnection.Free;
    end;
    
    WriteLn('Press Enter to exit...');
    ReadLn;
  except
    on E: Exception do
    begin
      WriteLn('Error: ' + E.Message);
      WriteLn('Press Enter to exit...');
      ReadLn;
    end;
  end;
end.