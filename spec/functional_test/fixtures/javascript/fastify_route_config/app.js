const fastify = require('fastify')()

// Multi-line route config with a single method.
fastify.route({
  method: 'GET',
  url: '/single',
  handler: async (request, reply) => {
    return reply.send(statusService.single())
  }
})

// Array `method` form covering multiple verbs.
fastify.route({
  method: ['GET', 'POST'],
  url: '/items/:id',
  handler: async (request, reply) => {
    return reply.send(buildItem(request.params.id))
  }
})

// Plural `methods:` is also accepted by some Fastify versions.
// Also exercises handler-body param extraction (request.body.*).
fastify.route({
  methods: ['PUT', 'PATCH'],
  url: '/users/:userId',
  handler: async (request, reply) => {
    const email = request.body.email
    return reply.send(UserService.update(email))
  }
})

// Verify single-line short form still works (regression).
fastify.get('/regression', async () => ({ ok: true }))

// Complex handler body with template literals, regex with braces, string with paren
fastify.route({
  method: 'POST',
  url: '/complex',
  handler: async (req, reply) => {
    const tmpl = `val: ${ { a: 1 } }`
    const re = /{[0-9]}/
    const s = "nested)paren"
    const title = req.body.title
    return reply.send({ ok: true, title })
  }
})

// Non-literal URL expression: matches main by emitting the leading string literal
fastify.route({
  method: 'GET',
  url: '/' + 'x',
  handler: async () => ({ ok: true })
})

module.exports = fastify
