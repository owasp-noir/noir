import type { TRPCRouterRecord } from "@trpc/server";
import { z } from "zod";
import { publicProcedure } from "../trpc";

export const searchProcs = {
  search: publicProcedure.input(z.object({ q: z.string() })).query(({ input }) => input.q),
} satisfies TRPCRouterRecord;

// Never mounted: a record no router references serves nothing.
export const orphanProcs = {
  orphan: publicProcedure.query(() => 1),
};
