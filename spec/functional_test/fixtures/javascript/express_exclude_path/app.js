const express = require('express');
const app = express();

app.get('/api/users', (req, res) => res.json([]));

module.exports = app;
