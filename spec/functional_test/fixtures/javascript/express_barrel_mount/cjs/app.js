const express = require('express');
const routes = require('./routes');
const { admin } = require('./forward');

const app = express();
app.use('/api', routes.accounts);
app.use('/admin', admin);
app.use('/staff', admin);

for (const entry of ['/new', '/upcoming']) {
  app.get(entry, (req, res) => res.send(req.query.page));
}
