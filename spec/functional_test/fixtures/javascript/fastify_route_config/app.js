const fastify = require('fastify')()

// Multi-line route config with a single method.
fastify.route({
  method: 'GET',
  url: '/single',
  handler: async (request, reply) => {
    return { ok: true }
  }
})

// Array `method` form covering multiple verbs.
fastify.route({
  method: ['GET', 'POST'],
  url: '/items/:id',
  handler: async (request, reply) => {
    return { id: request.params.id }
  }
})

// Plural `methods:` is also accepted by some Fastify versions.
fastify.route({
  methods: ['PUT', 'PATCH'],
  url: '/users/:userId',
  handler: async (request, reply) => {
    return { ok: true }
  }
})

// Verify single-line short form still works (regression).
fastify.get('/regression', async () => ({ ok: true }))

module.exports = fastify
