import { router } from "../trpc";
import { meRouter } from "./me/_router";
import { slotsRouter } from "./slots/_router";

// Used for client types only: every sub-router is served by its own
// `pages/api/trpc/<name>/[trpc].ts`, never as `/api/trpc/slots.getSchedule`.
export const appRouter = router({
  slots: slotsRouter,
  me: meRouter,
});
