unit SQLiteDBInit;

interface

procedure InitializeSQLiteDatabase;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  FireDAC.Comp.Client,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Stan.Param,
  FireDAC.DApt,
  FireDAC.Comp.UI,
  FireDAC.Phys.SQLite;

procedure InitializeSQLiteDatabase;
var
  LConnection: TFDConnection;
  LQuery: TFDQuery;
  LDBPath: string;
begin
  LDBPath := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), '..\..\data\loggerpro_sqlite.db');
  
  // If database already exists, exit
  if TFile.Exists(LDBPath) then
    Exit;
  
  LConnection := TFDConnection.Create(nil);
  try
    // Configure connection
    LConnection.DriverName := 'SQLite';
    LConnection.Params.Values['Database'] := LDBPath;
    LConnection.Connected := True;
    
    // Configure SQLite for optimal performance
    LQuery := TFDQuery.Create(nil);
    try
      LQuery.Connection := LConnection;
      
      // Enable Write-Ahead Logging for better concurrency
      LQuery.SQL.Text := 'PRAGMA journal_mode = WAL';
      LQuery.ExecSQL;
      
      // Balance between safety and performance
      LQuery.SQL.Text := 'PRAGMA synchronous = NORMAL';
      LQuery.ExecSQL;
      
      // Use 10MB of memory for cache
      LQuery.SQL.Text := 'PRAGMA cache_size = -10000';
      LQuery.ExecSQL;
      
      // Store temporary tables in memory
      LQuery.SQL.Text := 'PRAGMA temp_store = MEMORY';
      LQuery.ExecSQL;
      
      // Use memory-mapped I/O (256MB)
      LQuery.SQL.Text := 'PRAGMA mmap_size = 268435456';
      LQuery.ExecSQL;
      
      // Create the logs table
      LQuery.SQL.Text := 
        'CREATE TABLE loggerpro_logs (' +
        '  id INTEGER PRIMARY KEY AUTOINCREMENT,' +
        '  log_type INTEGER NOT NULL,' +
        '  log_tag TEXT,' +
        '  log_message TEXT NOT NULL,' +
        '  log_timestamp DATETIME NOT NULL,' +
        '  log_thread_id INTEGER NOT NULL' +
        ')';
      LQuery.ExecSQL;
      
      // Create indexes for better query performance
      LQuery.SQL.Text := 'CREATE INDEX idx_loggerpro_logs_timestamp ON loggerpro_logs(log_timestamp)';
      LQuery.ExecSQL;
      
      LQuery.SQL.Text := 'CREATE INDEX idx_loggerpro_logs_type ON loggerpro_logs(log_type)';
      LQuery.ExecSQL;
      
      LQuery.SQL.Text := 'CREATE INDEX idx_loggerpro_logs_tag ON loggerpro_logs(log_tag)';
      LQuery.ExecSQL;
      
    finally
      LQuery.Free;
    end;
    
  finally
    LConnection.Free;
  end;
end;

end.