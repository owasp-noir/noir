import { z } from 'zod'
import { router, publicProcedure } from '../trpc'

export const userRouter = router({
  list: publicProcedure.query(() => UserService.list()),
  byId: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input }) => UserService.find(input.id)),
  create: publicProcedure
    .input(z.object({ name: z.string(), email: z.string() }))
    .mutation(({ input }) => {
      AuditLog.write(input.email)
      return UserService.create(input)
    }),
})
