import Koa from "koa";
import Router from "@koa/router";

async function requireLogin(ctx, next) {
  if (!ctx.isAuthenticated()) ctx.throw(401)
  await next()
}

const router = new Router()
const admin = new Router({ prefix: '/admin' })
admin.use(requireLogin)
admin.get('/items', async (ctx) => { ctx.body = [] })
router.get('/me', requireLogin, async (ctx) => { ctx.body = 'me' })
router.get('/whoami', async (ctx) => { ctx.body = ctx.state.user || null })
router.get('/mine', async (ctx) => {
  if (!ctx.state.user) ctx.throw(401)
  ctx.body = ctx.state.user
})

const scoped = new Router()
scoped.get('/before', async (ctx) => { ctx.body = 'open' })
scoped.use('/private', requireLogin)
scoped.get('/private/report', async (ctx) => { ctx.body = 'report' })
scoped.get('/public/report', async (ctx) => { ctx.body = 'report' })

function adminRoutes() {
  const inner = new Router()
  inner.use(requireLogin)
  return inner
}

function publicRoutes() {
  const inner = new Router()
  inner.get('/health', async (ctx) => { ctx.body = 'ok' })
  // inner.use(requireLogin)
  inner.get('/status', async (ctx) => { ctx.body = 'ok' })
  inner.use(requireLogin)
  return inner
}

const listed = new Router()
listed.use(['/admin', '/ops'], requireLogin)
listed.get('/ops/run', async (ctx) => { ctx.body = 'run' })
listed.get('/docs', async (ctx) => { ctx.body = 'docs' })
