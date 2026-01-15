import express from 'express';
import helmet from 'helmet';
import morgan from 'morgan';
import winston from 'winston';
import pg from 'pg';
import Redis from 'ioredis';
import { metricsMiddleware, metricsEndpoint } from './metrics.js';

const app = express();
const PORT = process.env.PORT || 3000;

// Initialize logger
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.Console({
      format: winston.format.simple(),
    }),
  ],
});

// Database connection pool
const pool = new pg.Pool({
  user: process.env.DB_USER || 'postgres',
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'credpal',
  password: process.env.DB_PASSWORD || 'postgres',
  port: process.env.DB_PORT || 5432,
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error', (err) => {
  logger.error('Unexpected error on idle client', err);
});

// Redis client
const redis = new Redis({
  host: process.env.REDIS_HOST || 'redis',
  port: process.env.REDIS_PORT || 6379,
});

// Middleware
app.use(helmet());
app.use(morgan('combined'));
app.use(express.json());
app.use(metricsMiddleware);

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'ok',
    timestamp: new Date().toISOString(),
  });
});

// Metrics endpoint
app.get('/metrics', metricsEndpoint);

// Status endpoint (Postgres + Redis)
app.get('/status', async (req, res) => {
  let dbStatus = 'disconnected';
  let redisStatus = 'disconnected';

  try {
    // Check Postgres
    const client = await pool.connect();
    await client.query('SELECT NOW()');
    client.release();
    dbStatus = 'connected';
  } catch (err) {
    logger.error('Postgres status error:', err);
    dbStatus = 'error';
  }

  try {
    // Check Redis
    const pong = await redis.ping();
    if (pong === 'PONG') redisStatus = 'connected';
  } catch (err) {
    logger.error('Redis status error:', err);
    redisStatus = 'error';
  }

  res.status(200).json({
    status: dbStatus === 'connected' && redisStatus === 'connected' ? 'healthy' : 'degraded',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    redis: redisStatus,
    uptime: process.uptime(),
  });
});

// Process endpoint
app.post('/process', async (req, res) => {
  try {
    const { data } = req.body;

    if (!data) {
      return res.status(400).json({
        error: 'Missing data field',
      });
    }

    // Store in database
    const client = await pool.connect();
    const result = await client.query(
      'INSERT INTO process_logs (data) VALUES ($1) RETURNING id',
      [JSON.stringify(data)]
    );
    client.release();

    logger.info(`Processed data with ID: ${result.rows[0].id}`);

    res.status(200).json({
      message: 'Data processed successfully',
      id: result.rows[0].id,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error('Process error:', error);
    res.status(500).json({
      error: 'Processing failed',
      message: error.message,
    });
  }
});

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: 'Endpoint not found',
  });
});

// Error handler
app.use((err, req, res, next) => {
  logger.error('Unhandled error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'An error occurred',
  });
});

// Start server
const server = app.listen(PORT, '0.0.0.0', () => {
  logger.info(`Server running on port ${PORT} in ${process.env.NODE_ENV || 'development'} mode`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  logger.info('SIGTERM signal received: closing HTTP server');
  server.close(() => {
    logger.info('HTTP server closed');
    pool.end(() => {
      logger.info('Database pool closed');
      process.exit(0);
    });
  });
});

export default app;
