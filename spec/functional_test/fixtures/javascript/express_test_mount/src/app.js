const express = require('express');
const users = require('./routes/users');

const app = express();
app.use('/api/v1/users', users);

module.exports = app;
