import { Hono } from 'hono';
const app = new Hono();

app.post('/h00-control', async (c) => {
  const { title } = await c.req.json();
  return c.json({ title });
});
app.post('/h01-var', async (c) => {
  const body = await c.req.json();
  return c.json({ a: body.title, b: body.slug });
});
app.post('/h02-var-destructure', async (c) => {
  const data = await c.req.json();
  const { email, password } = data;
  return c.json({ email, password });
});
app.post('/h03-typed', async (c) => {
  const { name, age } = await c.req.json<{ name: string; age: number }>();
  return c.json({ name, age });
});
app.post('/h04-form-var', async (c) => {
  const body = await c.req.parseBody();
  return c.json({ f: body['avatar'], g: body.caption });
});
app.get('/h05-query-destructure', (c) => {
  const { page, limit } = c.req.query();
  return c.json({ page, limit });
});
export default app;
