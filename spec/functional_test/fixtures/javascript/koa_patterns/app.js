const Koa = require('koa');
const Router = require('@koa/router');

const app = new Koa();
const router = new Router();

// Pattern 1: Case-insensitive HTTP methods
router.Get('/case-get', (ctx) => {
  const param = ctx.query.param1;
  ctx.body = { method: 'GET' };
});

router.Post('/case-post', (ctx) => {
  const { data } = ctx.request.body;
  ctx.body = { method: 'POST' };
});

router.Put('/case-put', (ctx) => {
  const { value } = ctx.request.body;
  ctx.body = { method: 'PUT' };
});

router.Delete('/case-delete', (ctx) => {
  ctx.body = { method: 'DELETE' };
});

// Pattern 2: Async handlers
router.get('/async-handler', async (ctx) => {
  const asyncParam = ctx.query.asyncParam;
  const data = await fetchData();
  ctx.body = { data };
});

// Pattern 3: Context variations
router.post('/ctx-variations', async (ctx) => {
  const { field1, field2 } = ctx.request.body;
  const query1 = ctx.query.query1;
  const header1 = ctx.headers['x-custom-header'];
  ctx.body = { success: true };
});

// Pattern 4: Template literal paths
const apiPrefix = '/api';
const version = 'v2';

router.get(`${apiPrefix}/${version}/template`, async (ctx) => {
  ctx.body = { template: true };
});

// Pattern 5: Concatenated paths
router.post(apiPrefix + '/' + version + '/concat', async (ctx) => {
  ctx.body = { concat: true };
});

// Pattern 6: Router with prefix
const apiRouter = new Router({
  prefix: '/api'
});

apiRouter.get('/users', async (ctx) => {
  const page = ctx.query.page;
  ctx.body = { users: [] };
});

apiRouter.post('/users', async (ctx) => {
  const { username, email } = ctx.request.body;
  ctx.body = { created: true };
});

// Mount routers
app.use(router.routes());
app.use(apiRouter.routes());

module.exports = app;

// Helper function
async function fetchData() {
  return {};
}
