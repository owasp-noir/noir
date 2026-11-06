const app = require('fastify')()

// Refuses everyone without a token, except routes whose config sets `public`.
app.addHook('onRequest', async (request, reply) => {
  if (request.routeOptions.config.public) return
  if (!request.headers.authorization) return reply.code(401).send()
})

app.get('/flag/private', async () => 'ok')
app.get('/flag/login', { config: { public: true } }, async () => 'ok')
