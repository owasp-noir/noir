import { router, publicProcedure } from '../trpc';

export const adminRouter = router({
  stats: publicProcedure.query(() => ({ users: 0 })),
});
