'use strict';
const Hapi = require('@hapi/hapi');

const init = async () => {
  const server = Hapi.server({ port: 3000 });

  await server.register(require('./plugins/users'), { routes: { prefix: '/api/users' } });
  await server.register([{ plugin: require('./plugins/orders'), routes: { prefix: '/api/orders' } }]);

  server.route({ method: 'GET', path: '/items/{id}', handler: (request, h) => request.params.id });

  await server.start();
};
init();
