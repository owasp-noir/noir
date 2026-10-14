'use strict';
exports.plugin = {
  name: 'users',
  register: async function (server, options) {
    server.route({
      method: 'POST',
      path: '/',
      handler: (request, h) => request.payload
    });
    server.route({ method: 'GET', path: '/{userId}', handler: () => [] });
  }
};
