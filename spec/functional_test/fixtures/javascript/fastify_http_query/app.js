const fastify = require('fastify')({ logger: true });

// Register HTTP QUERY method
fastify.addHttpMethod('QUERY', { hasBody: true });

// Shorthand route after registration
fastify.query('/search', async (request, reply) => {
  const q = request.query.q;
  const filter = request.body.filter;
  return { results: [] };
});

// Single-method route config declaration
fastify.route({
  method: 'QUERY',
  url: '/advanced-search',
  handler: async (request, reply) => {
    const term = request.body.term;
    return { ok: true };
  },
});

// Array form with multiple verbs
fastify.route({
  method: ['GET', 'QUERY'],
  url: '/items/:id',
  handler: async (request, reply) => {
    const id = request.params.id;
    return { id };
  },
});

// Routes inside plugin with prefix
const searchPlugin = async (fastify, options) => {
  fastify.query('/plugin-query', async (request, reply) => {
    const q = request.query.q;
    return { results: [] };
  });

  fastify.route({
    method: 'QUERY',
    url: '/plugin-route',
    handler: async (request, reply) => {
      return { ok: true };
    },
  });
};

fastify.register(searchPlugin, { prefix: '/api/v1' });

// Stray query on a non-fastify object should not be detected
const db = { query: (sql) => {} };
db.query('SELECT 1');

module.exports = fastify;
