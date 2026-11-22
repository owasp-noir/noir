import { Hono } from 'hono'

export function createCounter() {
  const counter = new Hono().basePath('/counter')
  counter.get('/total', c => c.text(c.req.query('unit')))
  return counter
}
