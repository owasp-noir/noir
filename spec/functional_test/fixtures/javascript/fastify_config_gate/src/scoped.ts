export default async function (app) {
  app.register(async (admin) => {
    // Refuses only the routes of this callback that set `role`.
    admin.addHook('onRequest', async (req, reply) => {
      if (req.routeOptions.config?.role) {
        if (!req.user) return reply.code(401).send()
      }
    })
    admin.get('/inside', { config: { role: 'admin' } }, async () => 'ok')
  })
  app.get('/outside', { config: { role: 'admin' } }, async () => 'ok')
}
