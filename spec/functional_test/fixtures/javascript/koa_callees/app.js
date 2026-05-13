const Koa = require('koa')
const Router = require('@koa/router')

const app = new Koa()
const router = new Router()

router.post('/users/:id', async ctx => {
  const id = ctx.params.id
  const actor = ctx.get('X-Actor')
  const payload = await parseBody(ctx)
  await serviceFactory().save(payload, id, actor)
  ;(AuditLog.write)('koa:create')

  ctx.body = serializeUser(payload)
})

router.get('/session', async ctx => {
  const sessionId = ctx.cookies.get('sessionId')
  const profile = await loadProfile(sessionId)

  ctx.body = profile
})

function parseBody(ctx) {
  return ctx.request.body
}

function serviceFactory() {
  return userService
}

function serializeUser(payload) {
  return { data: payload }
}

async function loadProfile(sessionId) {
  return { sessionId }
}

app.use(router.routes())
app.listen(3000)
