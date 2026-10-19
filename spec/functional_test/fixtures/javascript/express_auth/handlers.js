const express = require('express');
const { servePublicFiles } = require('./routes/fileServer');
const { searchProducts } = require('./routes/search');
const legacyRoutes = require('./routes/legacy');

const app = express();

// A router factory on a path is a mount prefix, not a route.
app.use('/legacy', legacyRoutes());

// A path-mounted handler that answers the request: a route for every
// method, and not its own guard even though it answers 403.
app.use('/ftp/:file', servePublicFiles());

// The handler lives in another file: its params and callees are the route's.
app.get('/rest/products/search', searchProducts());

module.exports = app;
