const fastify = require('fastify')()

fastify.route({
  method: ['GET', 'POST'],
  url: '/items/:id',
  handler: async (request, reply) => {
    return reply.send(itemsA.find(request.params.id))
  }
})

fastify.listen({ port: 3000 })
