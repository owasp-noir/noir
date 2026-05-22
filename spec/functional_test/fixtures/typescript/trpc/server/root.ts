import { router, publicProcedure } from './trpc'
import { userRouter } from './routers/user'
import { postRouter } from './routers/post'
import { accountRouter } from './routers/account'

export const appRouter = router({
  user: userRouter,
  post: postRouter,
  account: accountRouter,
  health: publicProcedure.query(() => 'ok'),
})

export type AppRouter = typeof appRouter
