const Koa = require('koa');
const Router = require('@koa/router');

const router = new Router({ prefix: '/api' });

router
  .get('/users', (ctx) => { ctx.body = []; })
  .post('/users', (ctx) => { ctx.body = {}; })
  .del('/users/:id', (ctx) => { ctx.body = {}; });

const app = new Koa();
app.use(router.routes());
