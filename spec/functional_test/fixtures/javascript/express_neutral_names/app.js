const express = require('express');
const app = express();

// === Test Case 1: Neutral names - middleware first, router after ===
// Neither 'check' nor 'api' contain "route" or "middleware" in their names
// Folder is /handlers/, not /routes/ or /middleware/
const api = require('./handlers/api');
const check = require('./utils/check');
app.use('/x', check, api);

// === Test Case 2: Inline require() NOT at end of args ===
// The require() is in the middle, followed by middleware
const mw = require('./utils/mw');
app.use('/y', require('./handlers/data'), mw);

// === Test Case 3: Multiple neutral identifiers ===
// All names are neutral: processor, handler, filter
const processor = require('./handlers/processor');
const handler = require('./handlers/handler');
const filter = require('./utils/filter');
app.use('/z', filter, processor, handler);

// === Test Case 4: Same-file with neutral names ===
const parent = express.Router();
const child = express.Router();
const guard = (req, res, next) => next();

child.get('/endpoint', (req, res) => res.json({}));
parent.use('/child', guard, child);
app.use('/parent', parent);

module.exports = app;
