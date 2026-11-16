import { Hono } from 'hono'
import { saveBook } from './handlers'

export const books = new Hono()

books.get('/', (c) => c.json([]))

// on() on a sub-app that index.ts mounts under /books.
books.on(['PUT', 'PATCH'], '/:id', async (c) => {
  const { title } = await c.req.json()
  return c.json({ id: c.req.param('id'), title })
})

books.on('POST', ['/', '/import'], saveBook)

// An event emitter's listener has the same call shape.
events.on('get', '/room/1', () => {})
