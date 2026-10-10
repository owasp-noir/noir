const express = require('express');
const usersRouter = express.Router();
usersRouter.get('/list', (req, res) => res.send('users'));
module.exports = { usersRouter };
