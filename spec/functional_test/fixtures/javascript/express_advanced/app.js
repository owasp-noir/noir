const express = require('express');
const app = express();

// Cross-file router mount
const userRoutes = require('./routes/users');
app.use('/api', userRoutes);

module.exports = app;
