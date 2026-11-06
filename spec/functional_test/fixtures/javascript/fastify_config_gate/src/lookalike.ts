import fp from 'fastify-plugin'

// Not the root instance, which server.ts makes with Fastify().
export const helper = fp(async (app) => {
  app.decorate('answer', 42)
})

export default async function (app) {
  app.addHook('onRequest', async (req, reply) => {
    if (req.routeOptions.config?.tier) {
      if (!req.user) return reply.code(401).send()
    }
  })
  app.get('/own', { config: { tier: 'gold' } }, async () => 'ok')
}
