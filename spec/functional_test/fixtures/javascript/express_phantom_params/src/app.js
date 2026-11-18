const express = require('express');
const app = express();
const items = express.Router({ mergeParams: true });
const orders = require('./orders');

// A write through a destructured alias sets a header; it reads nothing.
items.get('/plain', (req, res) => {
  const { headers } = req;
  headers['accept'] = 'application/json';
  headers.locale = 'en';
  req.headers['x-forced'] = '1';
  res.send('ok');
});

// Reading through the alias is still a read.
items.get('/read', (req, res) => {
  const { headers } = req;
  res.send(headers['x-token'] + headers.locale);
});

// mergeParams: the mount prefix supplies :uid.
items.get('/owner', (req, res) => {
  res.send(req.params.uid);
});

app.use('/users/:uid', items);
app.use('/orders', orders);
app.listen(3000);
