const fastify = require('fastify')();

fastify.register(require('./plugin'), { prefix: '/api' });

module.exports = fastify;
