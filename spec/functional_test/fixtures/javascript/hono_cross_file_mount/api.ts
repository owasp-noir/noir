import { Hono } from 'hono'

const api = new Hono()

api.get('/', (c) => {
  return c.json({ message: 'Hello' })
})

api.get('/posts', async (c) => {
  const limit = c.req.query('limit')
  return c.json({ posts: [], limit })
})

api.post('/posts', async (c) => {
  const { title, body } = await c.req.json()
  return c.json({ title, body }, 201)
})

api.get('/posts/:id', (c) => {
  const id = c.req.param('id')
  return c.json({ id })
})

export default api
