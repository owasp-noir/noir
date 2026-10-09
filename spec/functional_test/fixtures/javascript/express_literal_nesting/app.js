const express = require('express');
const app = express();

app.get('/list', (req, res) => {
  const q = req.query.q;
  const items = [1, 2];
  res.send(`<ul>${items.map(i => `<li>${i}</li>`)}</ul>`);
});

app.get('/greet', (req, res) => {
  const name = req.query.name;
  res.send(`${[name].map(n => `it's ${n}`)}`);
});

app.get('/count', (req, res) => {
  let i = Number(req.query.n);
  const half = i++ / 2;
  res.send(String(half));
});

app.get('/after', (req, res) => {
  res.send(req.query.token);
});
