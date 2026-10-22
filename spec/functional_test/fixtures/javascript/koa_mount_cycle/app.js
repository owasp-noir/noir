const Koa = require('koa');
const Router = require('@koa/router');
const a = require('./a');
const b = require('./b');
const app = new Koa();

// a -> b -> a cycle, with two parallel a -> b edges.
const root = new Router();
root.use('/r', a.routes());
a.use('/x', b.routes());
a.use('/z', b.routes());
b.use('/y', a.routes());
app.use(root.routes());

// Self-mount.
const health = new Router();
health.get('/health', (ctx) => { ctx.body = 'ok'; });
health.use('/v1', health.routes());
app.use(health.routes());

app.listen(3000);
