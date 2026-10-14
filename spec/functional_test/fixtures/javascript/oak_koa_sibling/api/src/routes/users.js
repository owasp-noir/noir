const Router = require('@koa/router');
const router = new Router();

router.get('/', (ctx) => { ctx.body = []; });
router.delete('/:id', (ctx) => { ctx.status = 204; });

module.exports = router;
