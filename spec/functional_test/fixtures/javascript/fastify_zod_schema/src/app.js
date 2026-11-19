const fastify = require('fastify')();
const { z } = require('zod');
const { createItemBody, listQuery, createItemSchema } = require('./schemas');

const sameFileBody = { type: 'object', properties: { localSku: { type: 'string' } } };

// control: schema object declared in the same file
fastify.post('/s00-same-file', { schema: { body: sameFileBody } }, async () => 1);

// schema parts imported from ./schemas (the layout fastify-cli / most projects use)
fastify.post('/s01-imported-parts', { schema: { body: createItemBody, querystring: listQuery } }, async () => 1);

// whole schema imported
fastify.post('/s02-imported-whole', { schema: createItemSchema }, async () => 1);

// fastify-type-provider-zod
fastify.post('/s03-zod-shorthand', {
  schema: {
    body: z.object({ zname: z.string(), zage: z.number().optional() }),
    querystring: z.object({ zq: z.string() }),
  },
}, async () => 1);

const ZBody = z.object({ zref: z.string() });
fastify.route({
  method: 'POST',
  url: '/s04-zod-route',
  schema: { body: ZBody, params: z.object({ id: z.string() }) },
  handler: async () => 1,
});

fastify.listen({ port: 3000 });
