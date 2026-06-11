import { Hono } from 'hono'

const app = new Hono()

// Single-method app.on (regression coverage)
app.on('GET', '/single', (c) => c.text('ok'))

// Array-method app.on (new coverage)
app.on(['GET', 'POST'], '/items/:id', (c) => {
  const id = c.req.param('id')
  return c.json(itemService.lookup(id))
})

// Lower-case methods inside array should normalize
app.on(['put', 'patch'], '/users/:userId', (c) => {
  const userId = c.req.param('userId')
  return c.json(UserService.update(userId))
})

export default app
