const express = require('express');
const app = express();

// Level 1: Mount level1Router at /api
const level1Router = require('./routes/level1');
app.use('/api', level1Router);

// Also a direct route on app for baseline testing
app.get('/health', (req, res) => res.json({ status: 'ok' }));

module.exports = app;
