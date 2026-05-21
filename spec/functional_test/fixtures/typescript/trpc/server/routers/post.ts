import { z } from 'zod'
import { router, publicProcedure } from '../trpc'

export const postRouter = router({
  list: publicProcedure.query(() => []),
  byId: publicProcedure
    .input(z.object({ postId: z.string() }))
    .query(({ input }) => input),
  liveFeed: publicProcedure.subscription(() => {
    return null
  }),
})
