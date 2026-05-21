const Koa = require('koa');
const Router = require('@koa/router');

const app = new Koa();
const accountsRouter = new Router();

accountsRouter.prefix('/api/accounts');

accountsRouter.get('account-list', '/list', (ctx) => {
  const page = ctx.query['page'];
  ctx.body = { page };
});

accountsRouter.post('/create', (ctx) => {
  const { account_id: accountId, name } = ctx.request.body;
  const requestId = ctx.get('X-Request-Id');
  ctx.body = { accountId, name, requestId };
});

app.use(accountsRouter.routes());

module.exports = app;
