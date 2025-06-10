const Router = require('koa-router');
const router = new Router({
  prefix: '/admin'
});

router.get('/settings', ctx => {
  ctx.body = { setting: 'admin_setting_value' };
});

module.exports = router;
