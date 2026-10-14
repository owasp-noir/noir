import Fastify from 'fastify'
import users from './routes/users.js'

const fastify = Fastify({ logger: true })

fastify.register(users, { prefix: '/api' })

fastify.register(async function (instance) {
  instance.get('/ping', async () => 'pong')
  instance.register(async (v2) => {
    v2.post('/echo', async (request) => request.body)
    v2.route({ method: 'PUT', url: '/config', handler: async () => ({}) })
  }, { prefix: '/v2' })
}, { prefix: '/internal' })

await fastify.listen({ port: 3000 })
