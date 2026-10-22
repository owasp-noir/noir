import { z } from 'zod'
import { router, publicProcedure } from './trpc'

export const appRouter = router({
  health: publicProcedure.query(() => 'ok'),
  echo: publicProcedure
    .input(z.object({ message: z.string() }))
    .mutation(({ input }) => input.message),
})

export type AppRouter = typeof appRouter
