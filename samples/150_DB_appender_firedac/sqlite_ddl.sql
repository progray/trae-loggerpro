-- SQLite DDL for LoggerPro SQLite Appender
-- This file creates the necessary tables and indexes for the logging system

-- Create the logs table
CREATE TABLE IF NOT EXISTS logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    log_type INTEGER NOT NULL,
    log_tag TEXT,
    log_message TEXT,
    log_timestamp DATETIME NOT NULL,
    thread_id TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_logs_timestamp ON logs(log_timestamp);
CREATE INDEX IF NOT EXISTS idx_logs_log_type ON logs(log_type);
CREATE INDEX IF NOT EXISTS idx_logs_log_tag ON logs(log_tag);

-- Optional: Create a view for common queries
CREATE VIEW IF NOT EXISTS v_logs_summary AS
SELECT 
    id,
    log_type,
    log_tag,
    log_message,
    log_timestamp,
    thread_id,
    created_at
FROM logs
ORDER BY log_timestamp DESC;

-- Create a function to clean old logs (VACUUM will be called separately)
-- This function deletes logs older than specified days
-- Usage: SELECT cleanup_old_logs(30); -- deletes logs older than 30 days
-- Note: SQLite doesn't support stored procedures, but you can use this in application code
-- Example SQL for cleanup:
-- DELETE FROM logs WHERE log_timestamp < datetime('now', '-30 days');
-- VACUUM; -- to reclaim space after deletion
