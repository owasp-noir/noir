import { Hono } from 'hono'

// basePath chained on construction.
const app = new Hono().basePath('/api')
app.get('/users', (c) => c.json([]))
app.post('/users/:id', (c) => c.json({}))

// basePath attached after construction.
const v2 = new Hono()
v2.basePath('/v2')
v2.get('/ping', (c) => c.text('pong'))

export default app
