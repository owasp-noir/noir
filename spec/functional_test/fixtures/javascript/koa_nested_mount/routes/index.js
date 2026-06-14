const Router = require('koa-router');
const router = new Router();
const api = new Router();

const users = require('./users-router');
const articles = require('./articles-router');

// Aggregate sub-routers into `api` (no prefix), then mount `api` under
// /api via the koa-router `.routes()` middleware chain.
api.use(users);
api.use(articles);

router.use('/api', api.routes());

module.exports = router;
