const express = require('express');
const { users, nested: { deep } } = require('./routes/users');
const { admin, opts = {} } = require('./routes/admin');

const app = express();
app.use('/api', users);
app.use('/adm', admin);
app.listen(3000);
