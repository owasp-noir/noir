'use strict';

const express = require('express');
const app = express();

app.get('/healthz', (req, res) => res.sendStatus(200));

module.exports = app;
