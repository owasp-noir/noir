import { z } from 'zod'
import { router, publicProcedure } from '../trpc'

export const userRouter = router({
  list: publicProcedure.query(() => []),
  byId: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input }) => input),
  create: publicProcedure
    .input(z.object({ name: z.string(), email: z.string() }))
    .mutation(({ input }) => input),
})
