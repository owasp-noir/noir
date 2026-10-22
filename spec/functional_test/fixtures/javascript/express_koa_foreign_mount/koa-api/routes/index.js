const Router = require('koa-router');
const router = new Router();
const api = new Router();

const users = require('./users-router');

// `api` aggregates the sub-router with no prefix of its own, then the
// whole aggregate is mounted under /api.
api.use(users);

router.use('/api', api.routes());

module.exports = router;
