import { z } from 'zod';
import { publicProcedure } from '../trpc';

export const updateProfileRoute = publicProcedure
  .input(z.object({ displayName: z.string() }))
  .mutation(async ({ input }) => input);
