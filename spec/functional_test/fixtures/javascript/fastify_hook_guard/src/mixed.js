const app = require('fastify')()

// Gates admin routes on config, and refuses every anonymous caller besides.
app.addHook('onRequest', async (req, reply) => {
  if (req.routeOptions.config?.permissions) {
    if (!req.isAdmin) throw app.httpErrors.unauthorized()
  }
  if (!req.user) return reply.code(401).send()
})

app.get('/a/plain', async () => 'ok')
