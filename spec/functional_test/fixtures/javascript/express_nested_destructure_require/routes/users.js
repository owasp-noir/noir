const express = require('express');
const users = express.Router();
users.get('/list', (req, res) => res.json([]));
module.exports = { users, nested: { deep: 1 } };
