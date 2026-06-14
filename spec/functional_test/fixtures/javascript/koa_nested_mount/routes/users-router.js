const Router = require('koa-router');
const router = new Router();

router.post('/users', (ctx) => {});
router.post('/users/login', (ctx) => {});
router.get('/user', (ctx) => {});

module.exports = router.routes();
