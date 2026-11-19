'use strict';
const Hapi = require('@hapi/hapi');
const routes = require('./api/notes');
const { taskRoutes } = require('./api/tasks');
const { adminRoutes } = require('./api/admin');

const localRoutes = [
  { method: 'GET', path: '/local/a', handler: (request, h) => request.query.q },
  { method: 'POST', path: '/local/b', handler: (request, h) => request.payload },
];

// Never handed to server.route(): not a route.
const draftRoutes = [
  { method: 'GET', path: '/draft', handler: () => 'draft' },
];

const init = async () => {
  const server = Hapi.server({ port: 5000, host: 'localhost' });

  server.route([{ method: 'GET', path: '/control', handler: () => 'ok' }]);
  server.route(localRoutes);
  server.route(routes);
  server.route(taskRoutes);
  server.route([...adminRoutes, { method: 'GET', path: '/mixed', handler: () => 'm' }]);

  await server.start();
};

init();
