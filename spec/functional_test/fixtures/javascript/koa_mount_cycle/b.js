const Router = require('@koa/router');
const router = new Router();
router.get('/b', (ctx) => { ctx.body = 'b'; });
module.exports = router;
