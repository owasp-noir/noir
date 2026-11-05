import Fastify from 'fastify'

const app = Fastify()

// Refuses every route that does NOT set `anonymous`: setting it opens the route.
app.addHook('onRequest', async (req, reply) => {
  if (!req.routeOptions.config?.anonymous) {
    if (!req.user) return reply.code(401).send()
  }
})

app.get('/inverse/anon', { config: { anonymous: true } }, async () => 'ok')

// Refuses the routes that set no `roles`, written as a negated group.
app.addHook('preHandler', async (req, reply) => {
  const roles = req.routeOptions.config?.roles
  if (!(roles && roles.length)) {
    if (!req.user) return reply.code(401).send()
  }
})

app.get('/inverse/roles', { config: { roles: ['x'] } }, async () => 'ok')
