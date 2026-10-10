const fastify = require('fastify')({ logger: true });
const apiRoutes = require('./routes/api');
const { adminRoutes } = require('./routes/admin');

fastify.register(apiRoutes, { prefix: '/api' });
fastify.register(adminRoutes, { prefix: 'admin' });
fastify.register(require('./routes/health'));

fastify.listen({ port: 3000 });
