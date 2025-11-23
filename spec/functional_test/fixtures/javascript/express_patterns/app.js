const express = require('express');
const router = express.Router();

// Pattern 1: Case-insensitive HTTP methods (common in TypeScript/modern JS)
router.Get('/case-get', (req, res) => {
  const param = req.query.param1;
  res.json({ method: 'GET' });
});

router.Post('/case-post', (req, res) => {
  const { data } = req.body;
  res.json({ method: 'POST' });
});

router.Put('/case-put', (req, res) => {
  const { value } = req.body;
  res.json({ method: 'PUT' });
});

router.Delete('/case-delete', (req, res) => {
  const id = req.params.id;
  res.json({ method: 'DELETE' });
});

router.Patch('/case-patch', (req, res) => {
  const { field } = req.body;
  res.json({ method: 'PATCH' });
});

// Pattern 2: async/await syntax
router.get('/async-simple', async (req, res) => {
  const asyncParam = req.query.asyncParam;
  const data = await fetchData();
  res.json({ data });
});

router.post('/async-complex', async (req, res) => {
  const { title, content } = req.body;
  const userId = req.header('User-Id');
  const token = req.cookies.authToken;
  await saveData(title, content);
  res.json({ saved: true });
});

// Pattern 3: Method chaining - should detect all methods
router.route('/chained-all')
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
  })
  .delete((req, res) => {
    res.json({ method: 'DELETE' });
  });

// Pattern 4: Arrow functions with named handlers
const namedHandler = (req, res) => {
  const arrowParam = req.query.arrowParam;
  res.json({ arrow: true });
};

router.get('/named-arrow', namedHandler);

// Pattern 5: Traditional function syntax
function traditionalHandler(req, res) {
  const tradParam = req.query.tradParam;
  res.json({ traditional: true });
}

router.get('/traditional-function', traditionalHandler);

// Pattern 6: Multiline with middleware
router.post(
  '/multiline-middleware',
  authMiddleware,
  validationMiddleware,
  (req, res) => {
    const { username, password } = req.body;
    const token = req.header('Authorization');
    res.json({ authenticated: true });
  }
);

// Pattern 7: req.get() method for headers
router.get('/header-get-method', (req, res) => {
  const customHeader = req.get('X-Custom-Header');
  const anotherHeader = req.get('X-Another-Header');
  res.json({ headers: true });
});

// Pattern 8: Bracket notation for query params
router.get('/bracket-query', (req, res) => {
  const param1 = req.query['param1'];
  const param2 = req.query['param2'];
  res.json({ query: true });
});

// Pattern 9: Bracket notation for cookies
router.get('/bracket-cookie', (req, res) => {
  const cookie1 = req.cookies['sessionId'];
  const cookie2 = req.cookies['trackingId'];
  res.json({ cookies: true });
});

// Pattern 10: Mixed destructuring and direct access
router.post('/mixed-params', (req, res) => {
  // Body destructuring
  const { field1, field2 } = req.body;
  // Body direct access
  const field3 = req.body.field3;
  // Body bracket
  const field4 = req.body['field4'];
  
  // Query destructuring
  const { qparam1, qparam2 } = req.query;
  // Query direct
  const qparam3 = req.query.qparam3;
  
  // Headers various
  const header1 = req.headers['x-header-1'];
  const header2 = req.header('X-Header-2');
  const header3 = req.get('X-Header-3');
  
  res.json({ mixed: true });
});

// Pattern 11: Express app-level routes (not router)
const app = express();

app.get('/app-level', (req, res) => {
  const appParam = req.query.appParam;
  res.json({ app: true });
});

app.post('/app-level-post', (req, res) => {
  const { appData } = req.body;
  res.json({ app: true });
});

// Pattern 12: Single-line arrow function
router.get('/single-arrow', (req, res) => res.json({ single: true }));

// Pattern 13: Shorthand property names in destructuring
router.post('/shorthand-destructure', (req, res) => {
  const { name, email, age } = req.body;
  res.json({ name, email, age });
});

// Pattern 14: Default values in destructuring
router.post('/default-destructure', (req, res) => {
  const { theme = 'light', language = 'en' } = req.body;
  res.json({ theme, language });
});

// Pattern 15: Nested destructuring
router.post('/nested-destructure', (req, res) => {
  const { user: { name, email }, settings: { notifications } } = req.body;
  res.json({ name, email, notifications });
});

module.exports = router;

// Helper functions
function authMiddleware(req, res, next) { next(); }
function validationMiddleware(req, res, next) { next(); }
async function fetchData() { return {}; }
async function saveData(title, content) { }
