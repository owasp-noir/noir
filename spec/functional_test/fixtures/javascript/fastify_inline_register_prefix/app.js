const fastify = require('fastify')({ logger: true })

fastify.register(function (instance, options, done) {
  instance.get('/hello', (req, reply) => {
    reply.send({ greet: 'hello' })
  })
  done()
}, { prefix: '/english' })

fastify.register(function (instance, options, done) {
  instance.get('/hello', (req, reply) => {
    reply.send({ greet: 'ciao' })
  })
  done()
}, { prefix: '/italian' })
