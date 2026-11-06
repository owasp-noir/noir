import fp from 'fastify-plugin'

// A fastify-plugin: its hook reaches the routes of its parent.
async function gatePlugin(app) {
  app.addHook('onRequest', async (req, reply) => {
    if (req.routeOptions.config?.vip) {
      if (!req.user) return reply.code(401).send()
    }
  })
}

export default fp(gatePlugin)
