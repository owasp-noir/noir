import type { Context } from 'hono'

export async function saveBook(c: Context) {
  const isbn = c.req.query('isbn')
  return c.json({ isbn }, 201)
}
