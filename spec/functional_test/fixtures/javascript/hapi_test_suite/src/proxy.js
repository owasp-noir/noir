// A hapi route in a file that also imports axios: still a server file.
const Hapi = require('@hapi/hapi');
const axios = require('axios');

const server = Hapi.server({ port: 3001 });

server.route({
  method: 'GET',
  path: '/hapi-proxy',
  handler: async () => (await axios.get('https://upstream.example')).data,
});

module.exports = server;
