import { router, publicProcedure } from './trpc'
import { userRouter } from './routers/user'
import { postRouter } from './routers/post'

export const appRouter = router({
  user: userRouter,
  post: postRouter,
  health: publicProcedure.query(() => 'ok'),
})

export type AppRouter = typeof appRouter
