import Fastify from 'fastify';

const app = Fastify();

interface ListQuery { limit: number; offset: number }

// control: no type argument
app.get('/g00-control', async (request, reply) => {
  return request.query.limit;
});

// Fastify TS docs: "Using Generics"
app.get<{ Querystring: ListQuery }>('/g01-generic', async (request, reply) => {
  return request.query.limit;
});

app.get<{ Querystring: { a: string } }>('/g02-inline-generic', async (request, reply) => {
  return request.query.a;
});

app.post<{ Body: { title: string; done: boolean } }>('/g03-body', async (request, reply) => {
  const { title, done } = request.body;
  return { title, done };
});

app.get<{
  Querystring: ListQuery;
  Headers: { 'x-trace': string };
}>('/g04-multiline-generic', async (request, reply) => {
  return request.headers['x-trace'];
});

app.listen({ port: 3000 });
