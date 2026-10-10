const restify = require('restify');
const usersRouter = require('./routes/users');
const { adminRouter } = require('./routes/admin');

const server = restify.createServer();
usersRouter.applyRoutes(server, '/users');
adminRouter.applyRoutes(server, '/admin');
require('./routes/api').applyRoutes(server, '/api');
server.listen(8080);
