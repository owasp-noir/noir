const app = require('fastify')()

// Lets `public` routes through only for GET: a public POST is still refused.
app.addHook('onRequest', async (request, reply) => {
  if (request.routeOptions.config.public && request.method === 'GET') return
  if (!request.headers.authorization) return reply.code(401).send()
})

app.post('/b/pubpost', { config: { public: true } }, async () => 'ok')
