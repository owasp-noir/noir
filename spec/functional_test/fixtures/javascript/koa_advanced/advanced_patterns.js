const Koa = require('koa');
const Router = require('@koa/router');

const app = new Koa();
const router = new Router();

// Case-insensitive HTTP method patterns (Koa Router supports these)
router.Get('/mixed-get', (ctx) => {
  const mixedParam = ctx.query.mixedParam;
  ctx.body = { method: 'GET' };
});

router.Post('/mixed-post', (ctx) => {
  const { data } = ctx.request.body;
  ctx.body = { method: 'POST' };
});

router.Put('/mixed-put', (ctx) => {
  const { value } = ctx.request.body;
  ctx.body = { method: 'PUT' };
});

router.Delete('/mixed-delete', (ctx) => {
  const id = ctx.params.id;
  ctx.body = { method: 'DELETE' };
});

router.Patch('/mixed-patch', (ctx) => {
  const { field } = ctx.request.body;
  ctx.body = { method: 'PATCH' };
});

// Multi-line route definitions
router.get(
  '/multiline-simple',
  (ctx) => {
    const ml_param = ctx.query.ml_param;
    ctx.body = { multiline: true };
  }
);

router.post(
  '/multiline-with-middleware',
  authMiddleware,
  (ctx) => {
    const { username, password } = ctx.request.body;
    const authToken = ctx.headers.authorization;
    ctx.body = { authenticated: true };
  }
);

// Async/await patterns (idiomatic Koa)
router.get('/async-get', async (ctx) => {
  const asyncParam = ctx.query.asyncParam;
  const data = await fetchData();
  ctx.body = { data };
});

router.post('/async-post', async (ctx) => {
  const { title, content } = ctx.request.body;
  const userId = ctx.headers['user-id'];
  await saveData(title, content);
  ctx.body = { saved: true };
});

// Path parameters with multiple segments
router.get('/users/:userId/posts/:postId', (ctx) => {
  const { userId, postId } = ctx.params;
  const includeComments = ctx.query.includeComments;
  ctx.body = { userId, postId };
});

// Different parameter extraction patterns
router.post('/extract-variations', (ctx) => {
  // Destructuring from body
  const { field1, field2, field3 } = ctx.request.body;
  
  // Direct access
  const directField = ctx.request.body.directField;
  
  // Query params - different styles
  const query1 = ctx.query.query1;
  const query2 = ctx.query['query2'];
  const query3 = ctx.request.query.query3;
  
  // Headers - different styles
  const header1 = ctx.headers['x-custom-header'];
  const header2 = ctx.header['x-another-header'];
  const header3 = ctx.get('X-Third-Header');
  
  // Cookies
  const cookie1 = ctx.cookies.get('sessionId');
  const cookie2 = ctx.cookies.get('trackingId');
  
  ctx.body = { success: true };
});

// Nested routers (common Koa pattern)
const apiRouter = new Router({ prefix: '/api' });

apiRouter.get('/status', (ctx) => {
  const format = ctx.query.format;
  const statusKey = ctx.headers['x-status-key'];
  ctx.body = { status: 'active' };
});

apiRouter.put('/config', (ctx) => {
  const { theme, notifications } = ctx.request.body;
  const configToken = ctx.cookies.get('configToken');
  ctx.body = { updated: true };
});

// Multi-line in nested router
apiRouter.post(
  '/data',
  async (ctx) => {
    const { values } = ctx.request.body;
    const dataKey = ctx.headers['data-key'];
    ctx.body = { processed: true };
  }
);

// Admin router with further nesting
const adminRouter = new Router({ prefix: '/admin' });

adminRouter.get('/dashboard', async (ctx) => {
  const view = ctx.query.view;
  const adminToken = ctx.headers['admin-token'];
  ctx.body = { dashboard: {} };
});

adminRouter.post('/users/create', async (ctx) => {
  const { username, role, permissions } = ctx.request.body;
  const masterKey = ctx.cookies.get('masterKey');
  ctx.body = { created: true };
});

// Multi-line in admin router
adminRouter.get(
  '/system/logs',
  async (ctx) => {
    const date = ctx.query.date;
    const level = ctx.query.level;
    ctx.body = { logs: [] };
  }
);

// Using router.use for sub-routes
const v1Router = new Router();

v1Router.get('/profile', (ctx) => {
  const fields = ctx.query.fields;
  const userId = ctx.headers['x-user-id'];
  ctx.body = { profile: {} };
});

v1Router.post('/settings', (ctx) => {
  const { theme, language } = ctx.request.body;
  const sessionToken = ctx.cookies.get('sessionToken');
  ctx.body = { updated: true };
});

// Mount nested router
apiRouter.use('/v1', v1Router.routes());

// Route with both params and query
router.get('/items/:category/:id', (ctx) => {
  const { category, id } = ctx.params;
  const sort = ctx.query.sort;
  const filter = ctx.query.filter;
  ctx.body = { category, id };
});

// AllowedMethods (Koa-specific for handling OPTIONS, etc.)
router.all('/catchall', (ctx) => {
  const method = ctx.method;
  const anyParam = ctx.query.anyParam;
  ctx.body = { method };
});

// Named routes (Koa Router feature)
router.get('named-route', '/named', (ctx) => {
  const namedParam = ctx.query.namedParam;
  ctx.body = { named: true };
});

// Route with prefix parameter
router.param('userId', (id, ctx, next) => {
  ctx.user = { id };
  return next();
});

router.get('/user/:userId/profile', (ctx) => {
  const profileFields = ctx.query.fields;
  ctx.body = { user: ctx.user };
});

// Redirect routes
router.redirect('/old-path', '/new-path');

// Multiple middleware in route
router.get(
  '/with-middleware',
  authMiddleware,
  validationMiddleware,
  async (ctx) => {
    const middlewareParam = ctx.query.middlewareParam;
    ctx.body = { withMiddleware: true };
  }
);

// Arrow function variations
const handleArrow = (ctx) => {
  const arrowParam = ctx.query.arrowParam;
  ctx.body = { arrow: true };
};

router.get('/arrow-function', handleArrow);

// Mount all routers
app.use(router.routes());
app.use(router.allowedMethods());
app.use(apiRouter.routes());
app.use(apiRouter.allowedMethods());
app.use(adminRouter.routes());
app.use(adminRouter.allowedMethods());

// Helper functions
async function authMiddleware(ctx, next) { await next(); }
async function validationMiddleware(ctx, next) { await next(); }
async function fetchData() { return {}; }
async function saveData(title, content) { }

module.exports = app;
