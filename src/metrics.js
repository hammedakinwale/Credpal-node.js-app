import express from 'express';

const app = express();

// Custom metrics
const metricsData = {
  requestCount: 0,
  errorCount: 0,
  responseTime: [],
  startTime: Date.now(),
};

export const metricsMiddleware = (req, res, next) => {
  const startTime = Date.now();

  res.on('finish', () => {
    metricsData.requestCount++;
    metricsData.responseTime.push(Date.now() - startTime);

    if (res.statusCode >= 400) {
      metricsData.errorCount++;
    }
  });

  next();
};

export const metricsEndpoint = (req, res) => {
  const uptime = Date.now() - metricsData.startTime;
  const avgResponseTime = metricsData.responseTime.length > 0
    ? metricsData.responseTime.reduce((a, b) => a + b, 0) / metricsData.responseTime.length
    : 0;

  res.json({
    uptime: Math.floor(uptime / 1000),
    requestCount: metricsData.requestCount,
    errorCount: metricsData.errorCount,
    errorRate: metricsData.requestCount > 0
      ? (metricsData.errorCount / metricsData.requestCount * 100).toFixed(2) + '%'
      : '0%',
    avgResponseTime: avgResponseTime.toFixed(2) + 'ms',
    memory: {
      rss: Math.round(process.memoryUsage().rss / 1024 / 1024) + 'MB',
      heapTotal: Math.round(process.memoryUsage().heapTotal / 1024 / 1024) + 'MB',
      heapUsed: Math.round(process.memoryUsage().heapUsed / 1024 / 1024) + 'MB',
      external: Math.round(process.memoryUsage().external / 1024 / 1024) + 'MB',
    },
  });
};
