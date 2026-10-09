// A plugin's instance is whatever the plugin function names it; the
// route()/query() passes must not assume `fastify`/`app`/`server`.
const fastify = require('fastify')();
fastify.addHttpMethod('QUERY', { hasBody: true });

fastify.get('/g', async () => 'g');

async function plugin(api, opts) {
  api.route({
    method: 'POST',
    url: '/r1',
    handler: async (request) => request.body.name,
  });
  api.route({ method: ['GET'], url: '/r4', handler: async () => 1 });
  api.query('/q1', async (request) => request.query.term);
}

// Not routes: a database call and a handler-less helper call.
const db = { query: (sql) => sql };
db.query('SELECT * FROM users', () => {});
const helper = { query: (path) => path };
helper.query('/not-a-route');

fastify.register(plugin);
