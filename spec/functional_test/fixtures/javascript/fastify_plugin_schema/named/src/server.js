const fastify = require('fastify')()
fastify.register(async function privateRoutes (app) {
  app.get('/tasks', async () => [])
}, { prefix: '/api' })
fastify.listen({ port: 3000 })
