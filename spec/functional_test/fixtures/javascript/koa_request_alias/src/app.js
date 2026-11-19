const Koa = require('koa');
const Router = require('@koa/router');
const router = new Router();

router.post('/k00-control', async (ctx) => {
  ctx.body = { a: ctx.request.body.title, b: ctx.query.page };
});
router.post('/k01-alias', async (ctx) => {
  const body = ctx.request.body;
  const query = ctx.query;
  ctx.body = { a: body.title, c: query.page };
});
router.post('/k02-alias-destructure', async (ctx) => {
  const data = ctx.request.body;
  const { email, password } = data;
  ctx.body = { email, password };
});
router.post('/k03-ctx-destructure', async (ctx) => {
  const { request, params } = ctx;
  const { body } = ctx.request;
  ctx.body = { a: request.body.viaRequest, b: body.viaBody };
});
module.exports = router;
