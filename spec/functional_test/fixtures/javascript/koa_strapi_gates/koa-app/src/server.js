const Koa = require('koa');
const Router = require('@koa/router');

const app = new Koa();
const router = new Router();

router.get('/_health', (ctx) => {
  ctx.body = 'ok';
});

app.use(router.routes());
app.listen(3000);
