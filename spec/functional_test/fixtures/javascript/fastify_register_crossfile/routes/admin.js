async function adminRoutes(fastify, opts) {
  fastify.get('/stats', async () => ({}));
}

module.exports = { adminRoutes };
