const fastify = require('fastify')()

const ListQuery = {
  type: 'object',
  properties: { page: { type: 'integer' }, status: { type: 'string' } }
}

fastify.get('/tasks', { schema: { querystring: ListQuery } }, async (request) => {
  return list(request.query)
})

fastify.post('/tasks', {
  schema: {
    body: {
      type: 'object',
      required: ['name'],
      properties: { name: { type: 'string' }, assignee: { type: 'integer' } }
    },
    headers: {
      type: 'object',
      properties: { 'x-tenant': { type: 'string' } }
    }
  }
}, async (request) => {
  return create(request.body)
})

fastify.route({
  method: 'PUT',
  url: '/tasks/:id',
  schema: { body: Type.Object({ title: Type.String() }) },
  handler: async (request) => update(request.body)
})
