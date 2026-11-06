const express = require('express');
const admin = express.Router();
admin.get('/stats', (req, res) => res.json({}));
module.exports = { admin, opts: {} };
