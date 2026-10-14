const Koa = require('koa');
const Router = require('@koa/router');
const users = require('./routes/users');

const app = new Koa();
const api = new Router({ prefix: '/api/v1' });
api.use('/users', users.routes());
app.use(api.routes());
app.listen(3000);
