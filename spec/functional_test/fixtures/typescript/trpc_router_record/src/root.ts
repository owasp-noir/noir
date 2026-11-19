import authRouter from "./router/auth";
import { postRouter } from "./router/post";
import { searchProcs } from "./router/search";
import { createTRPCRouter, publicProcedure } from "./trpc";

export const appRouter = createTRPCRouter({
  auth: authRouter,
  post: postRouter,
  health: publicProcedure.query(() => "ok"),
  ...searchProcs,
});

export type AppRouter = typeof appRouter;
