const express = require('express');
const usersRouter = require('./routes/users');
const { router: authRouter } = require('./routes/auth');
const v1 = express.Router();

const app = express();
app.use(express.json());

v1.use('/users', usersRouter);
v1.use('/auth', authRouter);
app.use('/api/v1', v1);

app.route('/health')
  .get((req, res) => res.send('ok'))
  .head((req, res) => res.end());

module.exports = app;
