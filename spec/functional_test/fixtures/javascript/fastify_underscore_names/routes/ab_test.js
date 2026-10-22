const fp = require('fastify-plugin');

// An A/B-test plugin: production code whose name ends in _test.
module.exports = fp(async function abTest(fastify) {
  fastify.get('/ab', async () => ({ variant: 'a' }));
});
