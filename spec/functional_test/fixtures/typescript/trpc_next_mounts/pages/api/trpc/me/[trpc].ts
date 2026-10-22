import { createNextApiHandler } from "@acme/trpc/server/createNextApiHandler";
import { meRouter } from "@acme/trpc/server/routers/me/_router";

export default createNextApiHandler(meRouter);
