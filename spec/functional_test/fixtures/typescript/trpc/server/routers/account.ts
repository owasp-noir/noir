import { z } from 'zod'
import { router, protectedProcedure, publicProcedure } from '../trpc'

const accountProcedures = {
  me: publicProcedure.query(() => AccountService.current()),
  update: protectedProcedure
    .input(z.object({ displayName: z.string() }))
    .mutation(({ input }) => AccountService.update(input)),
}

export const accountRouter: ReturnType<typeof router> = router(accountProcedures)
