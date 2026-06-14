import Fastify from 'fastify';
import AutoLoad from '@fastify/autoload';
import path from 'node:path';

const fastify = Fastify();

// dirNameRoutePrefix: false -> subdirectories do NOT become prefixes; a
// file's own `autoPrefix` export provides the prefix instead.
fastify.register(AutoLoad, {
  dir: path.join(import.meta.dirname, 'routes'),
  dirNameRoutePrefix: false,
});

fastify.listen({ port: 3000 });
