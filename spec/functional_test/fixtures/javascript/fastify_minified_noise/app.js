// Real Fastify server. Only these two routes should be detected. The
// sibling src/lib/vendor-bundle.js is a minified asset whose packed
// `fastify.route({...})` config must not leak through the auxiliary
// route-config pass (issue #1903 review coverage).
const fastify = require('fastify')()

fastify.route({
  method: 'GET',
  url: '/api/ping',
  handler: async (request, reply) => {
    return { ok: true }
  }
})

fastify.get('/api/health', async () => ({ status: 'ok' }))

module.exports = fastify
