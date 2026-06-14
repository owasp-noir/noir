const Koa = require('koa');
const router = require('./routes');

const app = new Koa();
app.use(router.routes());

app.listen(3000);
