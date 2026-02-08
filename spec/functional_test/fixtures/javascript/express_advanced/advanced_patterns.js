const express = require('express');
const router = express.Router();

// Case-insensitive HTTP method patterns
// Testing .Get, .Post, .Put, .Delete variations (common in ES6/TypeScript)
router.Get('/mixed-get', (req, res) => {
  const param = req.query.mixedParam;
  res.json({ method: 'GET' });
});

router.Post('/mixed-post', (req, res) => {
  const { data } = req.body;
  res.json({ method: 'POST' });
});

router.Put('/mixed-put', (req, res) => {
  const { value } = req.body;
  res.json({ method: 'PUT' });
});

router.Delete('/mixed-delete', (req, res) => {
  const id = req.params.id;
  res.json({ method: 'DELETE' });
});

router.Patch('/mixed-patch', (req, res) => {
  const { field } = req.body;
  res.json({ method: 'PATCH' });
});

// Multi-line route definitions (common in formatted code)
router.get(
  '/multiline-simple',
  (req, res) => {
    const ml_param = req.query.ml_param;
    res.json({ multiline: true });
  }
);

router.post(
  '/multiline-with-middleware',
  authMiddleware,
  (req, res) => {
    const { username, password } = req.body;
    const token = req.header('Authorization');
    res.json({ authenticated: true });
  }
);

// Async/await patterns (modern Express)
router.get('/async-get', async (req, res) => {
  const asyncParam = req.query.asyncParam;
  const data = await fetchData();
  res.json({ data });
});

router.post('/async-post', async (req, res) => {
  const { title, content } = req.body;
  const userId = req.header('User-Id');
  await saveData(title, content);
  res.json({ saved: true });
});

// Arrow function variations
const handleArrow = (req, res) => {
  const arrowParam = req.query.arrowParam;
  res.json({ arrow: true });
};

router.get('/arrow-function', handleArrow);

// Method chaining on routes (common pattern)
router.route('/chained')
  .get((req, res) => {
    const getParam = req.query.getParam;
    res.json({ method: 'GET' });
  })
  .post((req, res) => {
    const { postData } = req.body;
    res.json({ method: 'POST' });
  })
  .put((req, res) => {
    const { putData } = req.body;
    res.json({ method: 'PUT' });
  });

// Nested path parameters
router.get('/users/:userId/posts/:postId', (req, res) => {
  const { userId, postId } = req.params;
  const includeComments = req.query.includeComments;
  res.json({ userId, postId });
});

// Optional route parameters (common pattern)
router.get('/posts/:id?', (req, res) => {
  const id = req.params.id;
  const filter = req.query.filter;
  res.json({ id });
});

// Regex routes (advanced pattern)
router.get(/^\/regex-(\d+)$/, (req, res) => {
  const regexId = req.params[0];
  res.json({ regexMatch: true });
});

// Array of paths (express supports array routes)
router.get(['/array-a', '/array-b'], (req, res) => {
  res.json({ arrayMatch: true });
});

// Different parameter extraction patterns
router.post('/extract-variations', (req, res) => {
  // Destructuring from body
  const { field1, field2, field3 } = req.body;
  
  // Direct access
  const directField = req.body.directField;
  
  // Bracket notation
  const bracketField = req.body['bracketField'];
  
  // Query params - different styles
  const query1 = req.query.query1;
  const query2 = req.query['query2'];
  
  // Headers - different styles
  const header1 = req.headers['x-custom-header'];
  const header2 = req.header('X-Another-Header');
  const header3 = req.get('X-Third-Header');
  
  // Cookies
  const cookie1 = req.cookies.sessionId;
  const cookie2 = req.cookies['trackingId'];
  
  res.json({ success: true });
});

// Template literal paths (ES6)
const apiPrefix = '/api';
const version = 'v2';

router.get(`${apiPrefix}/${version}/template`, (req, res) => {
  const templateParam = req.query.templateParam;
  res.json({ template: true });
});

// Concatenated paths
router.post(apiPrefix + '/' + version + '/concat', (req, res) => {
  const { concatData } = req.body;
  res.json({ concat: true });
});

// Multiple middleware with route
router.put(
  '/multiple-middleware',
  authMiddleware,
  validationMiddleware,
  rateLimitMiddleware,
  async (req, res) => {
    const { updateData } = req.body;
    const authToken = req.header('Authorization');
    await updateResource(updateData);
    res.json({ updated: true });
  }
);

// Express Router with prefix (common in modular apps)
const userRouter = express.Router();

userRouter.get('/profile', (req, res) => {
  const fields = req.query.fields;
  const userId = req.header('X-User-Id');
  res.json({ profile: {} });
});

userRouter.post('/settings', (req, res) => {
  const { theme, language, notifications } = req.body;
  const sessionToken = req.cookies.sessionToken;
  res.json({ updated: true });
});

router.use('/user', userRouter);

// Static file serving (should be detected)
router.use('/static', express.static('public'));

module.exports = router;

// Helper functions (not routes)
function authMiddleware(req, res, next) { next(); }
function validationMiddleware(req, res, next) { next(); }
function rateLimitMiddleware(req, res, next) { next(); }
async function fetchData() { return {}; }
async function saveData(title, content) { }
async function updateResource(data) { }
