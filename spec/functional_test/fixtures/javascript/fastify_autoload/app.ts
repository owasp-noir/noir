import Fastify from 'fastify';
import fastifyAutoload from '@fastify/autoload';
import path from 'node:path';

const app = Fastify();

// @fastify/autoload derives each route file's prefix from its directory
// path relative to `dir`. `routes/api/tasks/index.ts` therefore mounts
// under `/api/tasks`, even though the file registers `app.get('/:id')`.
app.register(fastifyAutoload, {
  dir: path.join(import.meta.dirname, 'routes'),
});

app.listen({ port: 3000 });
