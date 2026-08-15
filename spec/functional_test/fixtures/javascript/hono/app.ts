import { Hono } from 'hono'
import { getCookie } from 'hono/cookie'

const app = new Hono()

// Basic GET route
app.get('/', (c) => {
  const name = c.req.query('name')
  const apiKey = c.req.header('x-api-key')

  return c.json({ hello: 'world' })
})

// POST route with JSON body
app.post('/register', async (c) => {
  const { username, email, password } = await c.req.json()
  const clientId = c.req.header('client-id')

  return c.json({ success: true, userId: 123 })
})

// Route with path parameter
app.get('/users/:userId', (c) => {
  const userId = c.req.param('userId')
  const fields = c.req.query('fields')

  return c.json({ user: { id: userId } })
})

// Routes with different HTTP methods
app.get('/products', (c) => {
  const category = c.req.query('category')
  const limit = c.req.query('limit')

  return c.json({ products: [] })
})

app.post('/products', async (c) => {
  const { name, price, category } = await c.req.json()
  const storeId = c.req.header('store-id')

  return c.json({ success: true, id: 456 })
})

// Route with cookies
app.get('/dashboard', (c) => {
  const view = c.req.query('view')
  const sessionId = getCookie(c, 'sessionId')

  return c.json({ dashboard: 'data' })
})

// PUT route
app.put('/settings', async (c) => {
  const { theme, notifications } = await c.req.json()
  const authToken = c.req.header('authorization')

  return c.json({ updated: true })
})

// DELETE route with path param
app.delete('/users/:id', (c) => {
  const id = c.req.param('id')
  const adminKey = c.req.header('x-admin-key')

  return c.json({ deleted: true })
})

// PATCH route
app.patch('/users/:id/profile', async (c) => {
  const id = c.req.param('id')
  const { bio } = await c.req.json()

  return c.json({ updated: true })
})

// Form body with parseBody
app.post('/upload', async (c) => {
  const { file, description } = await c.req.parseBody()
  const uploadToken = c.req.header('x-upload-token')

  return c.json({ uploaded: true })
})

// app.on() with specific method
app.on('GET', '/health', (c) => {
  const format = c.req.query('format')

  return c.json({ status: 'ok' })
})

// QUERY route with JSON body (RFC 10008)
app.query('/search', async (c) => {
  const { query, filter } = await c.req.json()
  const apiKey = c.req.header('x-api-key')

  return c.json({ results: [] })
})

// app.on() with single QUERY method
app.on('QUERY', '/query-handler', async (c) => {
  const { keyword } = await c.req.json()

  return c.json({ status: 'ok' })
})

// app.on() with multi-verb array including QUERY
app.on(['GET', 'QUERY'], '/items/search', async (c) => {
  const filter = c.req.query('filter')

  return c.json({ items: [] })
})

// Sub-app / chained QUERY route
const subApp = new Hono().query('/nested-search', async (c) => {
  const { term } = await c.req.json()

  return c.json({ term })
})

export default app
