const express = require('express');
const ops = express.Router();
ops.get('/health', (req, res) => res.json({}));
module.exports = { ops, cfg: { a: { b: 1 } } };
