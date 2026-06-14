import { z } from 'zod'
// Regression guard: a tRPC router module that pulls in `react` (e.g. an
// RSC/client helper leaks through a shared import) must still be scanned —
// the client-side-framework filter is for the verb-DSL extractor only.
import { cache } from 'react'
import { router, protectedProcedure, publicProcedure } from '../trpc'

const accountProcedures = {
  me: publicProcedure.query(() => AccountService.current()),
  update: protectedProcedure
    .input(z.object({ displayName: z.string() }))
    .mutation(({ input }) => AccountService.update(input)),
}

export const accountRouter: ReturnType<typeof router> = router(accountProcedures)
