import { z } from 'zod'
import { router, publicProcedure } from '../trpc'

export const postRouter = router({
  list: publicProcedure.query(() => PostService.list()),
  byId: publicProcedure
    .input(z.object({ postId: z.string() }))
    .query(({ input }) => PostService.find(input.postId)),
  liveFeed: publicProcedure.subscription(() => {
    return FeedService.live()
  }),
})
