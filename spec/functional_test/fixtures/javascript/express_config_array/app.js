const express = require('express');
const routes = require('./routes/v1');

const app = express();

// Top-level mount: everything under /v1.
app.use('/v1', routes);

module.exports = app;
