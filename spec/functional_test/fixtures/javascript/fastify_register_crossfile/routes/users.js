module.exports = async function (fastify, opts) {
  fastify.get('/:id', async (request) => ({ id: request.params.id }));
  fastify.route({
    method: 'POST',
    url: '/',
    handler: async (request) => request.body,
  });
};
