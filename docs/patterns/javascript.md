# JavaScript Analyzer Pattern Support

This document describes the various code patterns supported by the JavaScript analyzers in OWASP Noir.

## Supported Frameworks

- Express.js
- Fastify
- Koa
- NestJS  
- Restify

## HTTP Method Patterns

### Case Variations
All analyzers support case-insensitive HTTP method names:

```javascript
// All of these are correctly detected:
router.get('/lowercase', handler);      // lowercase
router.Get('/capitalized', handler);     // Capitalized  
router.GET('/uppercase', handler);       // UPPERCASE
router.Post('/mixed', handler);          // Mixed case
```

### Supported Methods
- GET / get / Get
- POST / post / Post
- PUT / put / Put
- DELETE / delete / Delete
- PATCH / patch / Patch
- HEAD / head / Head
- OPTIONS / options / Options
- ALL / all / All

## Path Patterns

### String Literals
```javascript
router.get('/simple', handler);
router.get("/double-quotes", handler);
router.get(`/backticks`, handler);
```

### Dynamic Paths
```javascript
const prefix = '/api';
const version = 'v2';

// Template literals
router.get(`${prefix}/${version}/users`, handler);

// String concatenation
router.get(prefix + '/' + version + '/posts', handler);
```

### Path Parameters
```javascript
// Colon syntax (Express-style)
router.get('/users/:id', handler);
router.get('/posts/:postId/comments/:commentId', handler);

// Optional parameters
router.get('/items/:id?', handler);
```

## Handler Patterns

### Inline Handlers
```javascript
// Traditional function
router.get('/traditional', function(req, res) {
  res.json({});
});

// Arrow function
router.get('/arrow', (req, res) => {
  res.json({});
});

// Async handler
router.get('/async', async (req, res) => {
  const data = await fetchData();
  res.json({ data });
});

// Single-line arrow
router.get('/single', (req, res) => res.json({}));
```

### Multi-line Definitions
```javascript
router.post(
  '/multiline',
  middleware1,
  middleware2,
  (req, res) => {
    res.json({});
  }
);
```

### Method Chaining
```javascript
router.route('/chained')
  .get(handler)
  .post(handler)
  .put(handler)
  .delete(handler);
```

## Parameter Extraction

### Query Parameters
```javascript
// Direct access
const param1 = req.query.param1;

// Bracket notation
const param2 = req.query['param2'];

// Destructuring
const { param3, param4 } = req.query;
```

### Body Parameters
```javascript
// Direct access
const field1 = req.body.field1;

// Bracket notation
const field2 = req.body['field2'];

// Destructuring
const { field3, field4 } = req.body;

// With defaults
const { theme = 'light' } = req.body;
```

### Header Parameters
```javascript
// Bracket notation
const header1 = req.headers['x-custom-header'];

// Dot notation
const header2 = req.headers.authorization;

// header() method
const header3 = req.header('X-API-Key');

// get() method (Express)
const header4 = req.get('X-Request-ID');
```

### Cookie Parameters
```javascript
// Direct access
const cookie1 = req.cookies.sessionId;

// Bracket notation
const cookie2 = req.cookies['trackingId'];
```

### Path Parameters
```javascript
// Automatically extracted from URL pattern
router.get('/users/:userId', (req, res) => {
  const userId = req.params.userId; // Detected as path parameter
});
```

## Framework-Specific Patterns

### Express
```javascript
// App-level routes
app.get('/app-route', handler);

// Router-level routes
const router = express.Router();
router.get('/router-route', handler);

// Nested routers with prefix
app.use('/api', apiRouter);
```

### Fastify
```javascript
// Method shortcuts
fastify.get('/route', handler);

// Route configuration object
fastify.route({
  method: 'GET',
  url: '/config-route',
  handler: async (request, reply) => {}
});

// Multiple methods
fastify.route({
  method: ['GET', 'POST'],
  url: '/multi-method',
  handler: handler
});
```

### Koa
```javascript
// Router with prefix
const router = new Router({
  prefix: '/api'
});

router.get('/users', handler);
// Detected as: GET /api/users
```

## Known Limitations

1. **Named Handler Functions**: Parameters are not extracted when handlers are defined separately:
   ```javascript
   const namedHandler = (req, res) => {
     const param = req.query.param; // Not extracted
   };
   router.get('/route', namedHandler);
   ```

2. **Complex Files**: In very large files with many routes and complex patterns, some routes may be missed due to parser iteration limits.

3. **Nested Destructuring**: Limited support for deeply nested destructuring:
   ```javascript
   const { user: { name, email } } = req.body; // Limited support
   ```

4. **Regex Routes**: Routes defined with regular expressions are not fully supported:
   ```javascript
   router.get(/^\/regex-(\d+)$/, handler); // Not supported
   ```

## Testing

Test fixtures demonstrating these patterns are available in:
- `spec/functional_test/fixtures/javascript/express_patterns/`
- `spec/functional_test/fixtures/javascript/fastify_patterns/`
- `spec/functional_test/fixtures/javascript/koa_patterns/`

To test pattern detection:
```bash
./bin/noir -b spec/functional_test/fixtures/javascript/express_patterns/ -f json
```
