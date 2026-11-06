// An encapsulated plugin (no fastify-plugin): its hook covers its own routes only.
export default async function (app) {
  app.addHook('onRequest', async (req, reply) => {
    if (req.routeOptions.config?.level) {
      if (!req.user) return reply.code(401).send()
    }
  })
  app.get('/inside', { config: { level: 2 } }, async () => 'ok')
}
