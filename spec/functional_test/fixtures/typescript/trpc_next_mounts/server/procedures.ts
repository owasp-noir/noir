import { TRPCError } from "@trpc/server";
import { rateLimit } from "@acme/rate-limit";
import { isAuthed, perfMiddleware } from "./middlewares";
import { procedure } from "./trpc";

// A commented-out guard does not guard:
// const legacy = procedure.use(() => { throw new TRPCError({ code: "UNAUTHORIZED" }) });

export const publicProcedure = procedure.use(perfMiddleware);
export const authedProcedure = publicProcedure.use(isAuthed);
// Its middleware lives outside the scan: neither guarded nor anonymous.
export const limitedProcedure = procedure.use(rateLimit);
// A factory: the guard sits in the function body, the router calls it.
export const createPermProcedure = (permission: string) =>
  authedProcedure.use(async ({ next }) => {
    if (!permission) throw new TRPCError({ code: "FORBIDDEN" });
    return next();
  });
