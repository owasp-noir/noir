import { Hono } from 'hono'
import { bearerAuth } from 'hono/bearer-auth'
import { jwt } from 'hono/jwt'
import { basicAuth } from 'hono/basic-auth'

const app = new Hono()

// Public route
app.get('/public', (c) => c.json({ message: 'public' }))

// Using bearerAuth middleware on route
app.get('/api/secure', bearerAuth({ token: 'secret-token' }), (c) => {
  return c.json({ data: 'secure' })
})

// Using jwt middleware via .use() for a prefix
app.use('/admin/*', jwt({ secret: 'my-secret' }))

app.get('/admin/dashboard', (c) => {
  const payload = c.var.payload // set by jwt middleware
  return c.json({ user: payload })
})

// Basic auth on specific path
app.use('/basic/*', basicAuth({ username: 'admin', password: 'secret' }))

app.get('/basic/data', (c) => c.json({ ok: true }))

// Custom auth middleware (common pattern)
const authMiddleware = async (c: any, next: any) => {
  const auth = c.req.header('Authorization')
  if (!auth) return c.text('Unauthorized', 401)
  c.set('user', { id: 1 })
  await next()
}

app.use('/protected/*', authMiddleware)

app.get('/protected/profile', (c) => {
  const user = c.get('user')
  return c.json({ user })
})

// Chained inline style (common in Hono)
app.get('/me', authMiddleware, (c) => {
  return c.json({ me: true })
})

// Public health check (no auth nearby)
app.get('/health', (c) => c.json({ status: 'ok' }))

export default app
