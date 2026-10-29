import Router from '@koa/router'
export function initItemsRouter(): Router {
  const router = new Router()
  router.get('/list', async (ctx) => { ctx.body = [] })
  return router
}
