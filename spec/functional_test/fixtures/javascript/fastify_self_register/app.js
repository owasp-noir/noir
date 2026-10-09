const fastify = require('fastify')();

async function tree(f) {
  f.get('/node', async () => 'x');
  f.register(tree, { prefix: '/child' });
}

fastify.register(tree, { prefix: '/api' });
fastify.listen({ port: 3000 });
