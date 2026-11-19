const fastify = require('fastify')({ logger: true });
const routes = require('./routes');

fastify.route({ method: 'GET', url: '/control', handler: async () => 'ok' });

routes.forEach((route, index) => {
  fastify.route(route);
});

const localRoutes = [
  { method: 'GET', url: '/local/a', handler: async (request) => request.query.q },
  { method: 'PUT', url: '/local/b', handler: async () => 'b' },
];
for (const r of localRoutes) {
  fastify.route(r);
}

// Never handed to fastify.route(): not a route.
const draftRoutes = [
  { method: 'GET', url: '/draft', handler: async () => 'draft' },
];
draftRoutes.forEach((route) => console.log(route.url));

fastify.listen({ port: 3000 });
