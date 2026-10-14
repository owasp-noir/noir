'use strict';
module.exports = {
  name: 'orders',
  register(server) {
    server.route({ method: 'DELETE', path: '/{orderId}', handler: () => null });
  }
};
