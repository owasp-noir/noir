import { z } from 'zod';
import { publicProcedure } from '../trpc';

export const getUserRoute = publicProcedure
  .input(z.object({ id: z.string() }))
  .query(async ({ input }) => ({ id: input.id }));
