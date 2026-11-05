import Fastify from 'fastify'

const app = Fastify()

// Refuses the routes whose config sets `permissions` to a caller without a session.
app.addHook('preParsing', async (req, reply, payload) => {
  const perms = req.routeOptions.config?.permissions
  if (perms && perms.length > 0) {
    if (!req.session?.user) {
      throw app.httpErrors.unauthorized()
    }
  }
  return payload
})

// Lets the routes that set `publicAccess` through, refuses nothing itself.
app.addHook('onRequest', async (req, reply) => {
  if (req.routeOptions.config?.publicAccess) {
    return
  }
})

app.register(import('./api'), { prefix: '/api' })
app.register(import('./scoped'), { prefix: '/scoped' })
