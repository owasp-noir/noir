const Hapi = require('@hapi/hapi');
const Lab = require('@hapi/lab');

const lab = exports.lab = Lab.script();

lab.test('registers a route', async () => {
  const server = Hapi.server();
  server.route({ method: 'GET', path: '/hapi-test-only', handler: () => 'x' });
  await server.inject('/hapi-test-only');
});
