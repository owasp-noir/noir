const express = require('express');
const admin = express.Router();
const audit = express.Router();
admin.get('/stats', (req, res) => res.send('stats'));
audit.get('/log', (req, res) => res.send('log'));
module.exports = { adminRouter: admin, auditRouter: audit };
