const clients = require('restify-clients')

const client = clients.createJSONClient({
  url: 'http://localhost:8080',
})

client.get('/todo', function noop() {})
client.del('/todo/example', function noop() {})
