import { Hono } from 'hono'

// app.on() on a sub-app named neither app, router nor hono.
const app = new Hono()
const books = new Hono()

app.get('/g', (c) => c.text('g'))
books.on('GET', '/on1', (c) => c.text('on1'))
books.on(['GET', 'POST'], '/on2', (c) => {
  const id = c.req.query('id')
  return c.text(id)
})

app.route('/', books)

export default app
