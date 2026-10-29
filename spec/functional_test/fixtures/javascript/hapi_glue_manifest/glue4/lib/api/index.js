const register = (server, options, next) => {
  server.route([
    { method: 'GET', path: '/tags', handler: (request, reply) => reply({ tags: [] }) },
    { method: 'GET', path: '/articles/{slug}', handler: (request, reply) => reply({ slug: request.params.slug }) }
  ])
  return next()
}
register.attributes = { name: 'api' }
module.exports = register
