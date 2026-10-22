const Koa = require('koa');
const Router = require('@koa/router');
const users = require('./routes/users');

const app = new Koa();
const api = new Router();

api.use('/users', users.routes(), users.allowedMethods());
api.get('/health', (ctx) => { ctx.body = 'ok'; });

app.use(api.routes()).use(api.allowedMethods());
app.listen(3000);
