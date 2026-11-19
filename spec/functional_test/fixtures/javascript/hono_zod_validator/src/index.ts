import { Hono } from 'hono'
import { zValidator } from '@hono/zod-validator'
import { z } from 'zod'

const app = new Hono()

// Hono docs, Guides > Validation > "With Zod" / "Zod Validator Middleware"
app.post(
  '/posts',
  zValidator('json', z.object({ title: z.string(), content: z.string() })),
  zValidator('query', z.object({ draft: z.string().optional() })),
  (c) => {
    const { title, content } = c.req.valid('json')
    return c.json({ title, content }, 201)
  }
)

const loginForm = z.object({ username: z.string(), password: z.string() })
app.post('/login', zValidator('form', loginForm), (c) => c.json(c.req.valid('form')))

export default app
