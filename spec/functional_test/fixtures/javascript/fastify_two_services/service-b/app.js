const fastify = require('fastify')()

// A second service in the same repo serving the same address. Its route is
// its own endpoint declaration, not a duplicate of service-a's.
fastify.route({
  method: 'GET',
  url: '/items/:id',
  handler: async (request, reply) => {
    return reply.send(itemsB.find(request.params.id))
  }
})

fastify.route({
  method: 'DELETE',
  url: '/items/:id',
  handler: async (request, reply) => {
    return reply.send(itemsB.remove(request.params.id))
  }
})

fastify.listen({ port: 3001 })
