unit LoggerPro.SQLiteAppender.Cleanup;

interface

uses
  System.SysUtils,
  FireDAC.Comp.Client;

type
  TLoggerProSQLiteCleanup = class
  public
    class procedure CleanOldLogs(const Connection: TFDConnection; const TableName: string = 'logs'; const DaysToKeep: Integer = 30);
    class procedure CleanLogsByType(const Connection: TFDConnection; const TableName: string = 'logs'; const LogType: Integer; const DaysToKeep: Integer = 7);
    class procedure CleanLogsByTag(const Connection: TFDConnection; const TableName: string = 'logs'; const LogTag: string; const DaysToKeep: Integer = 7);
    class procedure VacuumDatabase(const Connection: TFDConnection);
    class function GetLogCount(const Connection: TFDConnection; const TableName: string = 'logs'): Int64;
    class function GetDatabaseSize(const Connection: TFDConnection): Int64;
  end;

implementation

{ TLoggerProSQLiteCleanup }

class procedure TLoggerProSQLiteCleanup.CleanOldLogs(const Connection: TFDConnection; const TableName: string; const DaysToKeep: Integer);
var
  SQL: string;
begin
  if not Connection.Connected then
    Connection.Connected := True;
    
  SQL := Format('DELETE FROM %s WHERE log_timestamp < datetime(''now'', ''-%d days'')', [TableName, DaysToKeep]);
  Connection.ExecSQL(SQL);
end;

class procedure TLoggerProSQLiteCleanup.CleanLogsByType(const Connection: TFDConnection; const TableName: string; const LogType: Integer; const DaysToKeep: Integer);
var
  SQL: string;
begin
  if not Connection.Connected then
    Connection.Connected := True;
    
  SQL := Format('DELETE FROM %s WHERE log_type = %d AND log_timestamp < datetime(''now'', ''-%d days'')', 
    [TableName, LogType, DaysToKeep]);
  Connection.ExecSQL(SQL);
end;

class procedure TLoggerProSQLiteCleanup.CleanLogsByTag(const Connection: TFDConnection; const TableName: string; const LogTag: string; const DaysToKeep: Integer);
var
  SQL: string;
begin
  if not Connection.Connected then
    Connection.Connected := True;
    
  SQL := Format('DELETE FROM %s WHERE log_tag = ''%s'' AND log_timestamp < datetime(''now'', ''-%d days'')', 
    [TableName, LogTag, DaysToKeep]);
  Connection.ExecSQL(SQL);
end;

class procedure TLoggerProSQLiteCleanup.VacuumDatabase(const Connection: TFDConnection);
begin
  if not Connection.Connected then
    Connection.Connected := True;
    
  Connection.ExecSQL('VACUUM');
end;

class function TLoggerProSQLiteCleanup.GetLogCount(const Connection: TFDConnection; const TableName: string): Int64;
var
  Query: TFDQuery;
begin
  Result := 0;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := Format('SELECT COUNT(*) FROM %s', [TableName]);
    Query.Open;
    Result := Query.Fields[0].AsLargeInt;
  finally
    Query.Free;
  end;
end;

class function TLoggerProSQLiteCleanup.GetDatabaseSize(const Connection: TFDConnection): Int64;
var
  Query: TFDQuery;
begin
  Result := 0;
  Query := TFDQuery.Create(nil);
  try
    Query.Connection := Connection;
    Query.SQL.Text := 'SELECT page_count * page_size as size FROM pragma_page_count(), pragma_page_size()';
    Query.Open;
    Result := Query.Fields[0].AsLargeInt;
  finally
    Query.Free;
  end;
end;

end.
