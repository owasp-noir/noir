import Fastify from 'fastify';
import AutoLoad from '@fastify/autoload';
import { join } from 'node:path';

const app = Fastify();

// `options.prefix` is handed to every plugin the root loads, in front of
// the directory-derived prefix.
app.register(AutoLoad, {
  dir: join(__dirname, 'modules'),
  options: { ...{}, prefix: '/api' },
  ignorePattern: /.*\.routes\.ts$/,
});

app.listen({ port: 3000 });
