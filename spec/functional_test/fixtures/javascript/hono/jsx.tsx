import { Hono } from 'hono'

const jsxApp = new Hono()

// The apostrophe in the JSX text is prose, not the start of a string.
jsxApp.get('/about', (c) => {
  const name = c.req.query('name')
  return c.html(<p>We don't track you, {name}</p>)
})

jsxApp.post('/submit', async (c) => {
  const token = c.req.header('X-Token')
  return c.text('ok')
})

export default jsxApp
