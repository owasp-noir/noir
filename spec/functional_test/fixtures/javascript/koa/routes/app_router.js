const Router = require('koa-router');
const router = new Router(); // Prefix will be applied in app.js with app.use('/app_prefix', ...)

router.get('/info', ctx => {
  ctx.body = { info: 'app_info' };
});

module.exports = router;
