const express = require('express');
const paths = require('./paths');
const orders = express.Router();

// `req.params.X` for an X the route does not declare is always undefined.
orders.get('/:id', (req, res) => {
  res.send(req.params.id + req.params.ghost);
});

orders.get('/const', (req, res) => {
  const { phantom } = req.params;
  res.send(phantom);
});

// The imported part of the path may declare `:id` itself.
orders.get(`${paths.base}/:x`, (req, res) => {
  res.send(req.params.id + req.params.x);
});

module.exports = orders;
