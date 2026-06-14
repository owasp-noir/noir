import { router } from './trpc';
import { adminRouter } from './admin/router';
import { userRouter } from './user/router';

export const appRouter = router({
  user: userRouter,
  admin: adminRouter,
});

export type AppRouter = typeof appRouter;
