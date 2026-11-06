const express = require('express');
const { users, nested: { deep } } = require('./routes/users');
const { admin, opts = {} } = require('./routes/admin');
const { ops, cfg: { a: { b } } } = require('./routes/ops');

const app = express();
app.use('/api', users);
app.use('/adm', admin);
app.use('/ops', ops);
app.listen(3000);
