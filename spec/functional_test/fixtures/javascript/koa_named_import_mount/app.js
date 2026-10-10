const Koa = require('koa');
const Router = require('@koa/router');
const { usersRouter } = require('./routes/users');
const { router: postsRouter } = require('./routes/posts');

const app = new Koa();
const router = new Router();
router.use('/users', usersRouter.routes());
router.use('/posts', postsRouter.routes());
app.use(router.routes());
