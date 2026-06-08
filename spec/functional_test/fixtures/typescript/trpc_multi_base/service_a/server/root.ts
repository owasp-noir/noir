import { initTRPC } from '@trpc/server'

const t = initTRPC.create()
const router = t.router
const publicProcedure = t.procedure

export const userRouter = router({
  list: publicProcedure.query(() => 'service-a'),
})

export const appRouter = router({
  user: userRouter,
})
