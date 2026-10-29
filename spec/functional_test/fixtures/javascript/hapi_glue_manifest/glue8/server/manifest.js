module.exports = {
  server: { port: 3000 },
  register: {
    plugins: [
      { plugin: '../lib', routes: { prefix: '/api' } },
      { plugin: '@hapi/inert' }
    ]
  }
}
