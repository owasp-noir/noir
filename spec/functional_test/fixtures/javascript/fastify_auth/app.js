const fastify = require('fastify')();

// Route with preHandler authenticate hook
fastify.get('/api/secure', { preHandler: authenticate }, async (req, reply) => {
  return { data: 'secure' };
});

// Route with onRequest authenticate
fastify.post('/api/data', { onRequest: authenticate }, async (req, reply) => {
  return { status: 'ok' };
});

// Route using fastify.authenticate decorator
fastify.get('/profile', { preHandler: [fastify.authenticate] }, async (req, reply) => {
  return { user: req.user };
});

// Route with generic verifyToken middleware
fastify.get('/dashboard', { preHandler: verifyToken }, async (req, reply) => {
  return { dashboard: true };
});










// Public route - no auth (far from auth patterns)
fastify.get('/public/health', async (req, reply) => {
  return { status: 'ok' };
});
