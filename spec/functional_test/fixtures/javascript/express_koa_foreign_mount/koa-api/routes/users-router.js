const Router = require('koa-router');
const router = new Router();

router.get('/users', (ctx) => {});
router.post('/users/login', (ctx) => {});

module.exports = router.routes();
