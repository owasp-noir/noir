import Router from '@koa/router'
export default function makeUsersRouter(): Router {
  const router = new Router()
  router.get('/me', async (ctx) => { ctx.body = {} })
  return router
}
