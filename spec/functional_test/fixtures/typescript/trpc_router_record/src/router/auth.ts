import { createTRPCRouter, protectedProcedure, publicProcedure } from "../trpc";

export default createTRPCRouter({
  getSession: publicProcedure.query(({ ctx }) => null),
  getSecretMessage: protectedProcedure.query(() => "secret"),
});
