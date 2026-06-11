import { Hono } from 'hono'

const auth = {
  local() {
    return async (c, next) => next()
  },
  remote() {
    return async (c, next) => next()
  },
  session(c) {
    return { user_id: c.req.header('x-user') }
  },
}

const todoService = (env, userId) => ({
  get() {
    return []
  },
  add(text) {
    return [{ text, userId }]
  },
})

export const TodoAPI = new Hono<{ Bindings: Env }>()
  .get('/todos', auth.local(), async (c) => {
    const { user_id } = auth.session(c)
    const todos = await todoService(c.env, user_id).get()
    return c.json({ todos })
  })
  .post('/todos', auth.remote(), async (c) => {
    const body = await c.req.json()
    const { user_id } = auth.session(c)
    const todos = await todoService(c.env, user_id).add(body.todoText)
    return c.json({ todos })
  })
