module.exports = async function (fastify, opts) {
  fastify.register(require('./users'), { prefix: '/users' });
  fastify.get('/status', async () => ({ ok: true }));
};
