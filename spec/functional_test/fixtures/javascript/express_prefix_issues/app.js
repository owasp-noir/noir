const express = require('express');
const app = express();

// === Test Case 1: Prefix bleed via file-level fallback ===
// This file exports two factory functions.
// We only mount createPublicRouter() at /api prefix.
// createAdminRouter() should NOT get the /api prefix.
const { createPublicRouter } = require('./routes/multi_export');
app.use('/api', createPublicRouter());

// === Test Case 2: Multiple identifiers in .use() ===
// The first identifier after the path should be the router.
// 'auth' is middleware, not a router.
const userRoutes = require('./routes/users');
const auth = require('./middleware/auth');
app.use('/users', userRoutes, auth);

// === Test Case 3: Same-file nested router with middleware ===
const nestedRouter = express.Router();
const subRouter = express.Router();
const logger = require('./middleware/logger');

subRouter.get('/items', (req, res) => res.json([]));
nestedRouter.use('/sub', subRouter, logger);
app.use('/nested', nestedRouter);

module.exports = app;
