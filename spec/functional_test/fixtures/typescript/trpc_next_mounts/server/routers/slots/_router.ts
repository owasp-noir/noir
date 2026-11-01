import { z } from "zod";
import { authedProcedure, createPermProcedure, limitedProcedure, publicProcedure } from "../../procedures";
import { router } from "../../trpc";
import { holdHandler } from "./hold.handler";

export const slotsRouter = router({
  getSchedule: publicProcedure.input(z.object({ from: z.string() })).query(async ({ input }) => {
    const { getScheduleHandler } = await import("./getSchedule.handler");
    return getScheduleHandler({ input });
  }),
  reserve: authedProcedure.mutation(async (opts) => (await import("./reserve.handler")).reserveHandler(opts)),
  hold: limitedProcedure.mutation(({ input }) => holdHandler({ input })),
  remove: createPermProcedure("slot.delete").mutation(() => "ok"),
  ping: publicProcedure.query(() => "pong"),
});
