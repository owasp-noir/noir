const app = require('fastify')()

// A config key joined with `||` to a credential test: refuses anonymous callers on every route.
app.addHook('onRequest', async (req, reply) => {
  if (!req.user || req.routeOptions.config?.admin) {
    return reply.code(401).send()
  }
})

app.get('/a/joined', async () => 'ok')
