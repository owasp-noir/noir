const restify = require('restify');
const Router = require('restify-router').Router;

// Create a server
const server = restify.createServer();

// Load plugins
server.use(restify.plugins.bodyParser()); // Parse JSON body data
server.use(restify.plugins.queryParser()); // Parse query parameters
server.use(restify.plugins.cookieParser()); // Parse cookies

// Traditional route definitions
function setupServer(server) {
    server.get('/', function(req, res, next) {
        var userAgent = req.header('X-API-Key');
        var paramName = req.query.name;

        res.send('index');
        return next();
    });

    server.post('/upload', function(req, res, next) {
        const auth = req.cookies.auth;
        const name = req.body.name;

        res.send('index');
        return next();
    });
    
    // Adding new endpoint with multiple verbs using method chaining
    server.get('/items', function(req, res, next) {
        const category = req.query.category;
        const sort = req.query.sort;
        res.json({ items: [] });
        return next();
    });
    
    server.post('/items', function(req, res, next) {
        const { name, description } = req.body;
        const csrfToken = req.header('X-CSRF-Token');
        res.json({ id: 123 });
        return next();
    });
    
    // Adding endpoint with route parameters
    server.get('/item/:itemId', function(req, res, next) {
        const itemId = req.params.itemId;
        const fields = req.query.fields;
        res.json({ item: { id: itemId } });
        return next();
    });
    
    // Adding versioned endpoint
    server.get({path: '/info', version: '1.0.0'}, function(req, res, next) {
        const format = req.query.format;
        res.json({ version: '1.0.0' });
        return next();
    });
}

// Setup using router pattern
const router = new Router();

// Define routes on the router
router.get('/api', function(req, res, next) {
    const token = req.header('Authorization');
    const page = req.query.page;
    
    res.json({ message: 'API endpoint' });
    return next();
});

router.post('/api/submit', function(req, res, next) {
    const { username, email } = req.body;
    const sessionId = req.cookies.sessionId;
    
    res.json({ success: true });
    return next();
});

// Route with path parameter
router.get('/users/:id', function(req, res, next) {
    const userId = req.params.id;
    const apiKey = req.headers['x-api-key'];
    
    res.json({ id: userId });
    return next();
});

// Adding nested router pattern
const adminRouter = new Router();
adminRouter.get('/dashboard', function(req, res, next) {
    const view = req.query.view;
    const adminKey = req.header('Admin-Key');
    res.json({ stats: [] });
    return next();
});

adminRouter.post('/users/create', function(req, res, next) {
    const { username, role } = req.body;
    const adminToken = req.cookies.adminToken;
    res.json({ created: true });
    return next();
});

adminRouter.applyRoutes(server, '/admin');

// Apply routes to server
setupServer(server);
router.applyRoutes(server);


// Using a differently named router variable
const apiRouter = new Router();
// apiRouter.applyRoutes(server, '/api/v1');

apiRouter.get('/products', function(req, res, next) {
    const limit = req.query.limit;
    res.json({ products: [] });
    return next();
});

// Adding more endpoints to this router
apiRouter.put('/products/:id', function(req, res, next) {
    const productId = req.params.id;
    const { price, stock } = req.body;
    const accessKey = req.header('X-Access-Key');
    res.json({ updated: true });
    return next();
});

apiRouter.del('/products/:id', function(req, res, next) {
    const productId = req.params.id;
    const confirmation = req.header('X-Confirm');
    res.json({ deleted: true });
    return next();
});



// Start server
server.listen(3000, function() {
    console.log('%s listening at %s', server.name, server.url);
});
