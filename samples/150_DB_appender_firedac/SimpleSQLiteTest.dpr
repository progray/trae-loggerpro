program SimpleSQLiteTest;

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
  FireDAC.Stan.Param;

procedure CreateSQLiteDatabase;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LDBPath: string;
begin
  LDBPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'data\loggerpro_sqlite.db');
  
  // Create data directory if it doesn't exist
  if not TDirectory.Exists(TPath.GetDirectoryName(LDBPath)) then
    TDirectory.CreateDirectory(TPath.GetDirectoryName(LDBPath));
  
  // Create connection
  LConnection := TFDConnection.Create(nil);
  try
    LConnection.DriverName := 'SQLite';
    LConnection.Params.Values['Database'] := LDBPath;
    LConnection.Connected := True;
    
    // Create table
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      LQuery.SQL.Text := 
        'CREATE TABLE IF NOT EXISTS loggerpro_logs (' +
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
        '  log_type INTEGER NOT NULL,' +
        '  log_tag TEXT,' +
        '  log_message TEXT NOT NULL,' +
        '  log_timestamp DATETIME NOT NULL,' +
        '  log_thread_id INTEGER NOT NULL' +
        ')';
      LQuery.ExecSQL;
      
      // Create indexes
      LQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_loggerpro_logs_timestamp ON loggerpro_logs(log_timestamp)';
      LQuery.ExecSQL;
      
      LQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_loggerpro_logs_type ON loggerpro_logs(log_type)';
      LQuery.ExecSQL;
      
      LQuery.SQL.Text := 'CREATE INDEX IF NOT EXISTS idx_loggerpro_logs_tag ON loggerpro_logs(log_tag)';
      LQuery.ExecSQL;
      
      WriteLn('SQLite database created successfully at: ' + LDBPath);
    finally
      LQuery.Free;
    end;
  finally
    LConnection.Free;
  end;
end;

procedure TestSQLiteConnection;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LDBPath: string;
begin
  LDBPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'data\loggerpro_sqlite.db');
  
  // Create connection with optimized settings
  LConnection := TFDConnection.Create(nil);
  try
    LConnection.DriverName := 'SQLite';
    LConnection.Params.Values['Database'] := LDBPath;
    LConnection.Params.Values['JournalMode'] := 'WAL';
    LConnection.Params.Values['Synchronous'] := 'Normal';
    LConnection.Params.Values['CacheSize'] := '-10000';
    LConnection.Params.Values['TempStore'] := 'Memory';
    LConnection.Params.Values['MMapSize'] := '268435456';
    LConnection.Params.Values['LockingMode'] := 'Normal';
    LConnection.Params.Values['BusyTimeout'] := '30000';
    LConnection.Params.Values['StringFormat'] := 'Unicode';
    LConnection.Connected := True;
    
    // Test insert
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      LQuery.SQL.Text := 
        'INSERT INTO loggerpro_logs (log_type, log_tag, log_message, log_timestamp, log_thread_id) ' +
        'VALUES (:log_type, :log_tag, :log_message, :log_timestamp, :log_thread_id)';
      
      // Insert test data
      LQuery.ParamByName('log_type').AsInteger := 1; // Info
      LQuery.ParamByName('log_tag').AsString := 'TEST';
      LQuery.ParamByName('log_message').AsString := 'This is a test message';
      LQuery.ParamByName('log_timestamp').AsDateTime := Now;
      LQuery.ParamByName('log_thread_id').AsInteger := GetCurrentThreadId;
      LQuery.ExecSQL;
      
      WriteLn('Test data inserted successfully');
      
      // Query data
      LQuery.SQL.Text := 'SELECT COUNT(*) AS LogCount FROM loggerpro_logs';
      LQuery.Open;
      var LLogCount := LQuery.FieldByName('LogCount').AsInteger;
      WriteLn(Format('Total logs in database: %d', [LLogCount]));
      LQuery.Close;
    finally
      LQuery.Free;
    end;
  finally
    LConnection.Free;
  end;
end;

begin
  try
    WriteLn('Creating SQLite database...');
    CreateSQLiteDatabase;
    
    WriteLn('Testing SQLite connection...');
    TestSQLiteConnection;
    
    WriteLn('SQLite test completed successfully.');
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