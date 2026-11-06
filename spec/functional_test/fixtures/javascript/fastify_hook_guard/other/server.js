const fastify = require('fastify')()

// Another package decorates the same name with a check that only logs:
// the refusing `checkToken` in ../src/plugins does not guard this one.
fastify.decorate('checkToken', async (request) => {
  try {
    await request.jwtVerify()
  } catch (err) {
    request.log.warn(err)
  }
})

fastify.get('/other/secure', { preHandler: [fastify.checkToken] }, async () => 'ok')
