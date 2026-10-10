const express = require('express');
const routes = require('./routes');
const { admin } = require('./routes');

const app = express();
app.use('/api', routes.accounts);
app.use('/admin', admin);
