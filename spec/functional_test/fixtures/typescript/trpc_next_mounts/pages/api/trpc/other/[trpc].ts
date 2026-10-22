import { createNextApiHandler } from "@acme/trpc/server/createNextApiHandler";
import { meRouter as otherRouter } from "@acme/trpc/server/routers/other/_router";

export default createNextApiHandler(otherRouter, true);
