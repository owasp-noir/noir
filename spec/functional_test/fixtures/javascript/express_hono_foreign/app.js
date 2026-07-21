const express = require('express');
const app = express();

app.get('/express-home', (req, res) => {
  const q = req.query.q;
  res.json({ q });
});

module.exports = app;
