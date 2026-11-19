import type { TRPCRouterRecord } from "@trpc/server";
import { z } from "zod";
import { protectedProcedure, publicProcedure } from "../trpc";

export const postRouter = {
  all: publicProcedure.query(({ ctx }) => []),
  byId: publicProcedure
    .input(z.object({ id: z.string() }))
    .query(({ input }) => input.id),
  create: protectedProcedure
    .input(z.object({ title: z.string(), content: z.string() }))
    .mutation(({ input }) => input),
  delete: protectedProcedure.input(z.string()).mutation(({ input }) => input),
} satisfies TRPCRouterRecord;
