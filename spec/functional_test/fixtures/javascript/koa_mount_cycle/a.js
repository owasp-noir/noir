const Router = require('@koa/router');
const router = new Router();
router.get('/a', (ctx) => { ctx.body = 'a'; });
module.exports = router;
