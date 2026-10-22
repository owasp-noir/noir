const Koa = require('koa');
const Router = require('@koa/router');
const items = require('../src/router');

const app = new Koa();
const outer = new Router({ prefix: '/koa-test-prefix' });
outer.use(items.routes());
app.use(outer.routes());
