const Router = require('@koa/router');

const router = new Router();
router.get('/items', async (ctx) => { ctx.body = []; });

module.exports = router;
