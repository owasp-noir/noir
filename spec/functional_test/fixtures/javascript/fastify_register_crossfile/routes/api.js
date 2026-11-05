module.exports = async function (fastify, opts) {
  fastify.register(require('./users'), { prefix: '/users' });
  // No prefix of its own: still served under this plugin's `/api`.
  fastify.register(require('./auth'));
  fastify.get('/status', async () => ({ ok: true }));
};
