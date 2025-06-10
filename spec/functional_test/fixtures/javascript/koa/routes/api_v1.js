const Router = require('koa-router');
const router = new Router(); // Prefix will be applied in app.js

router.get('/status', ctx => {
  ctx.body = { status: 'OK' };
});

module.exports = router;
