const Hapi = require('@hapi/hapi');

const server = Hapi.server({ port: 3000 });

server.route({
  method: 'GET',
  path: '/hapi-real',
  handler: () => 'ok',
});

module.exports = server;
