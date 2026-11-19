const express = require('express');
const app = express();
app.use(express.json());

app.post('/x00-control', (req, res) => {
  res.json({ a: req.body.title, b: req.query.page });
});

app.post('/x01-alias', (req, res) => {
  const body = req.body;
  const query = req.query;
  res.json({ a: body.title, b: body['slug'], c: query.page });
});

app.post('/x02-alias-destructure', (req, res) => {
  const data = req.body;
  const { email, password } = data;
  res.json({ email, password });
});

app.post('/x04-or-default', (req, res) => {
  const { limit = 10, offset = 0 } = req.query || {};
  const payload = req.body || {};
  res.json({ limit, offset, t: payload.token });
});
