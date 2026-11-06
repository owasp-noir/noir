import Fastify from 'fastify'

const app = Fastify()

// Both refuse the routes that do NOT set the key.
app.addHook('preValidation', async (req, reply) => {
  const tier = req.routeOptions.config?.tier
  if (typeof tier === 'undefined') {
    throw app.httpErrors.unauthorized()
  }
  const groups = req.routeOptions.config?.groups
  if (Array.isArray(groups) === false) {
    throw app.httpErrors.unauthorized()
  }
})

app.get('/inverse/tier', { config: { tier: 'gold', groups: ['a'] } }, async () => 'ok')
