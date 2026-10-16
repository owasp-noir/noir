const Koa = require('koa');
const Router = require('@koa/router');
const items = require('./router');

const app = new Koa();
const api = new Router({ prefix: '/api' });
api.use(items.routes());
app.use(api.routes());
