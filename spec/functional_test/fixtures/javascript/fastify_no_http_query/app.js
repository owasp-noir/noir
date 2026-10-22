const fastify = require('fastify')({ logger: true });

// Regular route
fastify.get('/users', async (request, reply) => {
  return { users: [] };
});

// Explicit route config with QUERY works even without addHttpMethod
fastify.route({
  method: 'QUERY',
  url: '/direct-query',
  handler: async (request, reply) => {
    return { ok: true };
  },
});

// Stray .query() calls without addHttpMethod('QUERY') should NOT produce QUERY endpoints
const db = { query: (sql) => {} };
db.query('SELECT * FROM users');

const helper = { query: (path) => {} };
helper.query('/not-a-route');

module.exports = fastify;
