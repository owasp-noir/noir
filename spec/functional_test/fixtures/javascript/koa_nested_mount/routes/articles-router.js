const Router = require('koa-router');
const router = new Router();

router.get('/articles', (ctx) => {});
router.get('/articles/:slug', (ctx) => {});

module.exports = router.routes();
