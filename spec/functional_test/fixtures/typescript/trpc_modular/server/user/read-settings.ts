import { publicProcedure } from '../trpc';

export const readSettingsRoute = publicProcedure.query(() => ({ theme: 'dark' }));
