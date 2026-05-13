import { Hono } from 'hono'
import { getCookie } from 'hono/cookie'

const app = new Hono()
const service = new UserService()

app.post('/users/:id', async (c) => {
  const id = c.req.param('id')
  const user = await parseUser(c)
  await serviceFactory().save(user, id)
  ;(AuditLog.write)('create')

  return c.json({ ok: true })
})

app.get('/profile', (c) => {
  const sessionId = getCookie(c, 'sessionId')
  const profile = buildProfile(sessionId)

  return c.json(profile)
})

app.on('GET', '/health', (c) => {
  const status = healthService.check()

  return c.json({ status })
})

async function parseUser(c) {
  return c.req.json()
}

function serviceFactory() {
  return service
}

function buildProfile(sessionId) {
  return { sessionId }
}
