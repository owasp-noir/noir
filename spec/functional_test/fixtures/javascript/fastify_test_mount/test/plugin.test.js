const t = require('tap');
const Fastify = require('fastify');

t.test('items', async (t) => {
  const app = Fastify();
  app.register(require('../src/plugin'), { prefix: '/fastify-test-prefix' });
  await app.inject('/fastify-test-prefix/items');
});
