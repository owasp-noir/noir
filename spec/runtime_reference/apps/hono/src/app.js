import { OpenAPIHono, createRoute } from '@hono/zod-openapi';
import { books, imported, mark, reply } from './routes/index.js';

const app = new OpenAPIHono();
app.use('*', mark);
const api = new OpenAPIHono();
api.route('/catalog', books);
app.route('/api', api);
app.route('/archive', books);

for (const path of ['/recent', '/popular', '/featured']) {
  app.get(path, reply);
}
const status = '/status';
app.get(`${status}/ready`, reply);
app.all('/echo', reply);

app.openapi(createRoute({
  method: 'post', path: '/orders', responses: { 200: { description: 'Created' } }
}), reply);
const cancel = createRoute({
  method: 'delete', path: '/orders/{id}', responses: { 200: { description: 'Cancelled' } }
});
app.openapi(cancel, reply);
app.openapi(imported, reply);
const draft = createRoute({
  method: 'get', path: '/unpublished', responses: { 200: { description: 'Draft' } }
});

export default app;
