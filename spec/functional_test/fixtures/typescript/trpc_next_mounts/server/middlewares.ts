import { TRPCError } from "@trpc/server";
import { middleware } from "./trpc";

export const perfMiddleware = middleware(async ({ next }) => {
  const result = await next();
  return result;
});

export const isAuthed = middleware(async ({ ctx, next }) => {
  if (!ctx.session) {
    throw new TRPCError({ code: "UNAUTHORIZED" });
  }
  return next({ ctx: { session: ctx.session } });
});
