const fastify = require('fastify')({ logger: true })

const service = new UserService()

fastify.post('/users/:id', async (request, reply) => {
  const id = request.params.id
  const user = await parseUser(request)
  await serviceFactory().save(user, id)
  ;(AuditLog.write)('create')

  return reply.send(user)
})

fastify.get('/profile', async (request, reply) => {
  const profile = await loadProfile(request.query.userId)

  return reply.send(profile)
})

async function parseUser(request) {
  return request.body
}

function serviceFactory() {
  return service
}

async function loadProfile(userId) {
  return { userId }
}
