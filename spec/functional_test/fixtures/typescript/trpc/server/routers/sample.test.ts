import { router, publicProcedure } from '../trpc'

export const testOnlyRouter = router({
  debug: publicProcedure.query(() => DebugService.status()),
})
