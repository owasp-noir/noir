const fastify = require('fastify')()

async function requireUser (request, reply) {
  if (!request.session.user) {
    return reply.code(401).send({ message: 'unauthorized' })
  }
}

fastify.register(async (app) => {
  app.addHook('onRequest', async (request, reply) => {
    if (request.url === '/api/auth/login') return
    if (!request.session.user) {
      return reply.code(401).send({ message: 'unauthorized' })
    }
  })

  app.get('/tasks', async () => [])

  app.delete('/tasks/:id', {
    preHandler: (request, reply) => request.isAdmin(reply)
  }, async (request) => ({ id: request.params.id }))

  app.post('/auth/login', async () => ({ token: 't' }))
}, { prefix: '/api' })

fastify.register(async (app) => {
  app.addHook('onRequest', async () => {})
  app.get('/health', async () => 'ok')
}, { prefix: '/public' })

fastify.get('/control', { onRequest: [fastify.authenticate] }, async () => 'ok')

fastify.get('/admin', { preHandler: requireUser }, async () => 'ok')

fastify.get('/inline', {
  preHandler: async (request, reply) => {
    if (!request.user) return reply.code(401).send()
  }
}, async () => 'ok')

fastify.get('/open', async () => 'ok')

// Decorated preHandlers, judged by their `decorate` definitions (plugins/auth.js).
fastify.get('/secure', { preHandler: [fastify.checkToken] }, async () => 'ok')
fastify.get('/maybe', { preHandler: [fastify.maybeUser] }, async () => 'ok')
fastify.get('/optional', { preHandler: [fastify.optionalToken] }, async () => 'ok')
