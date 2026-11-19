import { Hono } from 'hono';

// RPC style: every verb is a link of the chain on the new instance.
const books = new Hono()
  .get('/', (c) => c.json('list books'))
  .post('/', (c) => c.json('create a book', 201))
  .get('/:id', (c) => c.json(c.req.param('id')));

const app = new Hono()
  .basePath('/api')
  .get('/health', (c) => c.text('ok'))
  .route('/books', books);

// A path-less link serves the path of the link before it.
app
  .get('/endpoint', (c) => c.text('GET'))
  .post((c) => c.text('POST'))
  .delete((c) => c.text('DELETE'));

// basePath() returns a new instance; `root` itself stays unprefixed.
const root = new Hono();
root.get('/ping', (c) => c.text('pong'));
const v2 = root.basePath('/v2');
v2.get('/users', (c) => c.json([]));

export default app;
