import { createNextApiHandler } from "@trpc/server/adapters/next";
import { slotsRouter } from "../../../../server/routers/slots/_router";

export default createNextApiHandler({ router: slotsRouter });
