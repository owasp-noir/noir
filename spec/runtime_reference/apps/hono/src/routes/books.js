import { OpenAPIHono, createRoute } from '@hono/zod-openapi';

export const books = new OpenAPIHono();
export const reply = (c) => c.text('books');
export const mark = async (c, next) => { c.header('X-Catalog', 'books'); await next(); };

books.use('*', mark);
books.get('/books', reply);
books.post('/books', mark, reply);
books.get('/books/:id', reply);
books.get('/editions/:year?', reply);
books.get('/isbn/:number{[0-9]+}', reply);
books.get('/files/*', reply);

export const imported = createRoute({
  method: 'get', path: '/orders/{id}', responses: { 200: { description: 'Order' } }
});
