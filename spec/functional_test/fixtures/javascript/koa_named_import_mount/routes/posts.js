const Router = require('@koa/router');
const router = new Router();
router.get('/recent', (ctx) => { ctx.body = 'posts'; });
exports.router = router;
