const restify = require('restify');
const server = restify.createServer();

// Case-insensitive HTTP method patterns (Restify supports these)
server.Get('/mixed-get', (req, res, next) => {
  const mixedParam = req.query.mixedParam;
  res.send({ method: 'GET' });
  return next();
});

server.Post('/mixed-post', (req, res, next) => {
  const { data } = req.body;
  res.send({ method: 'POST' });
  return next();
});

server.Put('/mixed-put', (req, res, next) => {
  const { value } = req.body;
  res.send({ method: 'PUT' });
  return next();
});

server.Del('/mixed-delete', (req, res, next) => {
  const id = req.params.id;
  res.send({ method: 'DELETE' });
  return next();
});

server.Patch('/mixed-patch', (req, res, next) => {
  const { field } = req.body;
  res.send({ method: 'PATCH' });
  return next();
});

// Multi-line route definitions
server.get(
  '/multiline-simple',
  (req, res, next) => {
    const ml_param = req.query.ml_param;
    res.send({ multiline: true });
    return next();
  }
);

server.post(
  '/multiline-with-middleware',
  authMiddleware,
  (req, res, next) => {
    const { username, password } = req.body;
    const authToken = req.header('Authorization');
    res.send({ authenticated: true });
    return next();
  }
);

// Async/await patterns (modern Restify)
server.get('/async-get', async (req, res, next) => {
  const asyncParam = req.query.asyncParam;
  const data = await fetchData();
  res.send({ data });
  return next();
});

server.post('/async-post', async (req, res, next) => {
  const { title, content } = req.body;
  const userId = req.header('User-Id');
  await saveData(title, content);
  res.send({ saved: true });
  return next();
});

// Path parameters with multiple segments
server.get('/users/:userId/posts/:postId', (req, res, next) => {
  const { userId, postId } = req.params;
  const includeComments = req.query.includeComments;
  res.send({ userId, postId });
  return next();
});

// Different parameter extraction patterns
server.post('/extract-variations', (req, res, next) => {
  // Destructuring from body
  const { field1, field2, field3 } = req.body;
  
  // Direct access
  const directField = req.body.directField;
  
  // Query params - different styles
  const query1 = req.query.query1;
  const query2 = req.query['query2'];
  
  // Headers - different styles
  const header1 = req.headers['x-custom-header'];
  const header2 = req.header('X-Another-Header');
  
  // Cookies
  const cookie1 = req.cookies?.sessionId;
  const cookie2 = req.cookies?.trackingId;
  
  res.send({ success: true });
  return next();
});

// Restify Router (modular routes)
const Router = require('restify-router').Router;
const apiRouter = new Router();

apiRouter.get('/status', (req, res, next) => {
  const format = req.query.format;
  const statusKey = req.header('X-Status-Key');
  res.send({ status: 'active' });
  return next();
});

apiRouter.put('/config', (req, res, next) => {
  const { theme, notifications } = req.body;
  const configToken = req.cookies?.configToken;
  res.send({ updated: true });
  return next();
});

// Multi-line in router
apiRouter.post(
  '/data',
  async (req, res, next) => {
    const { values } = req.body;
    const dataKey = req.header('Data-Key');
    res.send({ processed: true });
    return next();
  }
);

// Admin router
const adminRouter = new Router();

adminRouter.get('/dashboard', async (req, res, next) => {
  const view = req.query.view;
  const adminToken = req.header('Admin-Token');
  res.send({ dashboard: {} });
  return next();
});

adminRouter.post('/users/create', async (req, res, next) => {
  const { username, role, permissions } = req.body;
  const masterKey = req.cookies?.masterKey;
  res.send({ created: true });
  return next();
});

// Multi-line in admin router
adminRouter.get(
  '/system/logs',
  async (req, res, next) => {
    const date = req.query.date;
    const level = req.query.level;
    res.send({ logs: [] });
    return next();
  }
);

// Apply routers with prefixes
apiRouter.applyRoutes(server, '/api/v2');
adminRouter.applyRoutes(server, '/admin');

// Route with both params and query
server.get('/items/:category/:id', (req, res, next) => {
  const { category, id } = req.params;
  const sort = req.query.sort;
  const filter = req.query.filter;
  res.send({ category, id });
  return next();
});

// Regex routes (Restify supports regex patterns)
server.get(/^\/regex-(\d+)$/, (req, res, next) => {
  const regexId = req.params[0];
  res.send({ regexMatch: true });
  return next();
});

// Named routes (Restify feature)
server.get({ name: 'named-route', path: '/named' }, (req, res, next) => {
  const namedParam = req.query.namedParam;
  res.send({ named: true });
  return next();
});

// Multiple middleware in route
server.get(
  '/with-middleware',
  authMiddleware,
  validationMiddleware,
  rateLimitMiddleware,
  async (req, res, next) => {
    const middlewareParam = req.query.middlewareParam;
    res.send({ withMiddleware: true });
    return next();
  }
);

// Arrow function variations
const handleArrow = (req, res, next) => {
  const arrowParam = req.query.arrowParam;
  res.send({ arrow: true });
  return next();
};

server.get('/arrow-function', handleArrow);

// Versioned routes (Restify versioning feature)
server.get({ path: '/versioned', version: '1.0.0' }, (req, res, next) => {
  const v1Param = req.query.v1Param;
  res.send({ version: '1.0.0' });
  return next();
});

server.get({ path: '/versioned', version: '2.0.0' }, (req, res, next) => {
  const v2Param = req.query.v2Param;
  res.send({ version: '2.0.0' });
  return next();
});

// Static file serving
server.get(/\/static\/?.*/, restify.plugins.serveStatic({
  directory: './public',
  default: 'index.html'
}));

// Pre and use handlers (middleware)
server.pre((req, res, next) => {
  const preParam = req.query.preParam;
  return next();
});

server.use((req, res, next) => {
  const useParam = req.query.useParam;
  return next();
});

// Opts route (Restify-specific for OPTIONS)
server.opts('/options-route', (req, res, next) => {
  const optParam = req.query.optParam;
  res.send({ method: 'OPTIONS' });
  return next();
});

// Head route
server.head('/head-route', (req, res, next) => {
  const headParam = req.query.headParam;
  res.send(200);
  return next();
});

// Param pre-processing (Restify feature)
server.param('userId', (req, res, next, userId) => {
  req.user = { id: userId };
  return next();
});

server.get('/user/:userId/profile', (req, res, next) => {
  const profileFields = req.query.fields;
  res.send({ user: req.user });
  return next();
});

// Helper functions
function authMiddleware(req, res, next) { return next(); }
function validationMiddleware(req, res, next) { return next(); }
function rateLimitMiddleware(req, res, next) { return next(); }
async function fetchData() { return {}; }
async function saveData(title, content) { }

module.exports = server;
