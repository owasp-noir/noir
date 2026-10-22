const Router = require('@koa/router');
const usersRouter = new Router();
usersRouter.get('/list', (ctx) => { ctx.body = 'users'; });
module.exports = { usersRouter };
