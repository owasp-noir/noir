exports.plugin = {
  name: 'app',
  register: async (server) => {
    server.route({ method: 'GET', path: '/ping', handler: () => 'pong' })
  }
}
