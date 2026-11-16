const fastify = require('fastify')()
const orders = require('./controllers/orders')
const orderService = require('./services/orders')

// Full declaration: the handler is a property of the route object.
fastify.route({
  method: 'GET',
  url: '/orders/:orderId',
  handler: orders.show,
})

// Shorthand with the handler in the options object.
fastify.post('/orders', { schema: { body: { type: 'object' } }, handler: orders.create })

// Method shorthand.
fastify.route({
  method: 'DELETE',
  url: '/orders/:orderId',
  async handler(request, reply) {
    return reply.send(await orderService.cancel(request.params.orderId))
  },
})

fastify.listen({ port: 3000 })
