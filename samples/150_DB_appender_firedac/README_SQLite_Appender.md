# LoggerPro SQLite Appender

这是一个高性能的 SQLite Appender 实现，专为 LoggerPro 框架设计，具有以下特性：

## 主要特性

1. **批量提交机制**：
   - 当内存累积达到 100 条日志时自动提交
   - 距离上次提交超过 500 毫秒时自动提交
   - 支持手动强制刷新缓冲区

2. **SQLite 性能优化**：
   - 启用 WAL（Write-Ahead Logging）模式提高并发性能
   - 设置 Synchronous 为 Normal 平衡安全性和性能
   - 使用内存映射 I/O 提高读写速度
   - 优化缓存设置

3. **多线程安全**：
   - 使用临界区保护内存缓冲区
   - 支持多线程并发写入
   - 最小化锁持有时间

4. **容错处理**：
   - 自动重试机制
   - 事务回滚保证数据一致性
   - 错误日志记录

## 使用方法

1. **创建 SQLite Appender**：
   ```pascal
   var
     SQLiteAppender: TLoggerProSQLiteAppender;
   begin
     // 创建连接字符串
     ConnectionString := 
       'DriverID=SQLite;' +
       'Database=path_to_your_database.db;' +
       'JournalMode=WAL;' +
       'Synchronous=Normal;' +
       'CacheSize=-10000;' +
       'TempStore=Memory;' +
       'MMapSize=268435456;' +
       'LockingMode=Normal;' +
       'BusyTimeout=30000;' +
       'StringFormat=Unicode';
     
     // 创建 Appender，批量大小 100，刷新间隔 500 毫秒
     SQLiteAppender := TLoggerProSQLiteAppender.Create(ConnectionString, 100, 500);
     
     // 创建日志写入器
     Log := LoggerProBuilder
       .WriteToAppender(SQLiteAppender)
       .Build;
   end;
   ```

2. **使用预配置的 SQLite Logger**：
   ```pascal
   // 直接使用全局函数
   SQLiteLog.Debug('Debug message', 'TAG');
   SQLiteLog.Info('Info message', 'TAG');
   SQLiteLog.Warn('Warning message', 'TAG');
   SQLiteLog.Error('Error message', 'TAG');
   SQLiteLog.Fatal('Fatal message', 'TAG');
   ```

3. **强制刷新缓冲区**：
   ```pascal
   if SQLiteLog is TLoggerProSQLiteAppender then
     TLoggerProSQLiteAppender(SQLiteLog).ForceFlush;
   ```

## 数据库结构

SQLite 数据库包含一个 `loggerpro_logs` 表，结构如下：

```sql
CREATE TABLE loggerpro_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    log_type INTEGER NOT NULL,           -- 0=Debug, 1=Info, 2=Warning, 3=Error, 4=Fatal
    log_tag TEXT,                        -- 可选的标签用于分类
    log_message TEXT NOT NULL,           -- 日志消息
    log_timestamp DATETIME NOT NULL,     -- 日志创建时间戳
    log_thread_id INTEGER NOT NULL       -- 生成日志的线程ID
);

-- 创建索引以提高查询性能
CREATE INDEX idx_loggerpro_logs_timestamp ON loggerpro_logs(log_timestamp);
CREATE INDEX idx_loggerpro_logs_type ON loggerpro_logs(log_type);
CREATE INDEX idx_loggerpro_logs_tag ON loggerpro_logs(log_tag);
```

## 性能优化建议

1. **批量大小**：根据应用需求调整批量大小，默认为 100
2. **刷新间隔**：根据实时性要求调整刷新间隔，默认为 500 毫秒
3. **数据库位置**：将 SQLite 数据库放在高速存储设备上
4. **定期维护**：定期执行 `VACUUM` 命令优化数据库

## 示例项目

示例项目位于 `samples\150_DB_appender_firedac` 目录下，包含：
- `LoggerPro.SQLiteAppender.pas` - SQLite Appender 实现
- `SQLiteDBInit.pas` - 数据库初始化单元
- `LoggerProConfig.pas` - 配置代码
- `FireDACAppenderFormU.pas` - 测试窗体

运行示例项目后，点击 "SQLite Appender Test" 按钮即可测试 SQLite Appender 功能。

## 注意事项

1. 确保有足够的磁盘空间存储日志数据
2. 定期备份重要的日志数据
3. 在高并发场景下，考虑增加批量大小和刷新间隔
4. 如果数据库文件损坏，可以从备份恢复或重新创建