-- SQLite DDL for LoggerPro SQLite Appender
-- This table structure is optimized for high-performance logging

-- Drop table if it exists
DROP TABLE IF EXISTS loggerpro_logs;

-- Create the logs table with optimized structure
CREATE TABLE loggerpro_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    log_type INTEGER NOT NULL,           -- 0=Debug, 1=Info, 2=Warning, 3=Error, 4=Fatal
    log_tag TEXT,                        -- Optional tag for categorization
    log_message TEXT NOT NULL,           -- The log message
    log_timestamp DATETIME NOT NULL,     -- Timestamp when the log was created
    log_thread_id INTEGER NOT NULL       -- Thread ID that generated the log
);

-- Create indexes for better query performance
CREATE INDEX idx_loggerpro_logs_timestamp ON loggerpro_logs(log_timestamp);
CREATE INDEX idx_loggerpro_logs_type ON loggerpro_logs(log_type);
CREATE INDEX idx_loggerpro_logs_tag ON loggerpro_logs(log_tag);

-- Configure SQLite for optimal performance
-- These settings will be applied programmatically when connecting:
-- PRAGMA journal_mode = WAL;          -- Enable Write-Ahead Logging for better concurrency
-- PRAGMA synchronous = NORMAL;        -- Balance between safety and performance
-- PRAGMA cache_size = -10000;        -- Use 10MB of memory for cache
-- PRAGMA temp_store = MEMORY;        -- Store temporary tables in memory
-- PRAGMA mmap_size = 268435456;      -- Use memory-mapped I/O (256MB)