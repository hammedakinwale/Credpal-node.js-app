-- Initialize database schema
CREATE TABLE IF NOT EXISTS process_logs (
  id SERIAL PRIMARY KEY,
  data JSONB NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_process_logs_created_at 
ON process_logs(created_at DESC);

-- Create index for JSONB queries
CREATE INDEX IF NOT EXISTS idx_process_logs_data 
ON process_logs USING gin(data);

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO postgres;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO postgres;
