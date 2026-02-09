const express = require('express');
const app = express();

// === Test Case 1: Prefix bleed via file-level fallback ===
// This file exports two factory functions.
// We only mount createPublicRouter() at /api prefix.
// createAdminRouter() should NOT get the /api prefix.
const { createPublicRouter } = require('./routes/multi_export');
app.use('/api', createPublicRouter());

// === Test Case 2: Router FIRST, middleware after ===
// userRoutes is the router (first), auth is middleware (last)
const userRoutes = require('./routes/users');
const auth = require('./middleware/auth');
app.use('/users', userRoutes, auth);

// === Test Case 3: Middleware FIRST, router after ===
// validate is middleware (first), orderRoutes is the router (last)
const orderRoutes = require('./routes/orders');
const validate = require('./middleware/validate');
app.use('/orders', validate, orderRoutes);

// === Test Case 4: Same-file nested router - router first ===
const nestedRouter = express.Router();
const subRouter = express.Router();
const logger = require('./middleware/logger');

subRouter.get('/items', (req, res) => res.json([]));
nestedRouter.use('/sub', subRouter, logger);
app.use('/nested', nestedRouter);

// === Test Case 5: Same-file nested router - middleware first ===
const nested2Router = express.Router();
const sub2Router = express.Router();
const rateLimit = require('./middleware/rateLimit');

sub2Router.get('/data', (req, res) => res.json({}));
nested2Router.use('/sub2', rateLimit, sub2Router);
app.use('/nested2', nested2Router);

module.exports = app;
