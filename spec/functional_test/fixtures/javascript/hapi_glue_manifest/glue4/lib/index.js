const Glue = require('glue')
const manifest = {
  connections: [{ port: 8080 }],
  registrations: [{ plugin: { register: './api' }, options: { routes: { prefix: '/api' } } }]
}
Glue.compose(manifest, { relativeTo: __dirname }, (err, server) => {
  if (err) throw err
  server.start(() => {})
})
