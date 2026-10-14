export default async function users(fastify) {
  fastify.get('/a', async () => 1)
  fastify.register(async (v) => {
    v.get('/b', async () => 2)
  }, { prefix: '/v2' })
}
