import { Hono } from 'hono'

const api = new Hono()
api.get('/todos', (c) => c.json([]))
api.post('/todos', (c) => c.json({}))
api.delete('/todos/:id', (c) => c.json({}))

export default api
