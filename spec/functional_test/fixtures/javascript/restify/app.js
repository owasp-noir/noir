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

// Apply routes to server
setupServer(server);
router.applyRoutes(server);

// Using a differently named router variable
const apiRouter = new Router();

apiRouter.get('/products', function(req, res, next) {
    const limit = req.query.limit;
    res.json({ products: [] });
    return next();
});

apiRouter.applyRoutes(server, '/api/v1');

// Start server
server.listen(3000, function() {
    console.log('%s listening at %s', server.name, server.url);
});
