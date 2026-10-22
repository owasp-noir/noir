const Fastify = require('fastify');

describe('ping', () => {
  it('replies', async () => {
    const fastify = Fastify();
    fastify.get('/phantom-ping', async () => 'pong');
  });
});
