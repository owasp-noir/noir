const express = require('express');
const app = express();

app.get('/page', (req, res) => {
  const name = req.query.name;
  const el = <div>{name}</div>;
  res.send(render(el));
});

app.post('/submit', (req, res) => {
  res.send(req.body.t);
});

app.get('/users/:id', (req, res) => {
  res.send(req.params.id);
});
