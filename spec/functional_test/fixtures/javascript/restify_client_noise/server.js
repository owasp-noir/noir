const restify = require('restify')

const server = restify.createServer()

server.get('/todo', function listTodos(req, res, next) {
  return next()
})

server.del('/todo/:name', function deleteTodo(req, res, next) {
  return next()
})
