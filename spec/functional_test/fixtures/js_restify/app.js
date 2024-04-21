const restify = require('restify');

function setupServer(server) {
    server.get('/', function(req, res, next) {
        var userAgent = req.header('X-API-Key');
        var paramName = req.query.name;

        res.send('index'); // Assuming 'index' is a simple response for demonstration
        return next();
    });

    server.post('/upload', function(req, res, next) {
        // Restify does not parse cookies by default, so you need to use a plugin or middleware if you want to access cookies
        // const auth = req.cookies.auth; // This line needs adjustment if using cookies
        const name = req.body.name;

        res.send('index'); // Similarly, adjust according to your actual response handling
        return next();
    });
}

// Setup Restify server
const server = restify.createServer();

server.use(restify.plugins.bodyParser()); // Parse JSON body data
// server.use(restify.plugins.cookieParser()); // Uncomment if you need cookie parsing

setupServer(server);

server.listen(3000, function() {
    console.log('%s listening at %s', server.name, server.url);
});
