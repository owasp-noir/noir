import Fastify from 'fastify'

const app = Fastify()

// Refuses the routes that set no `roles`, written as a negated group.
app.addHook('preHandler', async (req, reply) => {
  const roles = req.routeOptions.config?.roles
  if (!(roles && roles.length)) {
    if (!req.user) return reply.code(401).send()
  }
})

app.get('/inverse/roles', { config: { roles: ['x'] } }, async () => 'ok')
app.get('/inverse/noroles', async () => 'ok')
