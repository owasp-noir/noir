const fp = require('fastify-plugin')

module.exports = fp(async (fastify) => {
  // jwtVerify throws a 401; the catch sends it.
  fastify.decorate('checkToken', async (request, reply) => {
    try {
      await request.jwtVerify()
    } catch (err) {
      return reply.send(err)
    }
  })

  // The failure is only logged: anonymous callers get through.
  fastify.decorate('maybeUser', async (request) => {
    try {
      await request.jwtVerify()
    } catch (err) {
      request.log.debug(err)
    }
  })

  // Verified only when a token is sent.
  fastify.decorate('optionalToken', async (request) => {
    if (request.headers.authorization) await request.jwtVerify()
  })
})
