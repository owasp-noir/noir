import { createRoute, z } from "@hono/zod-openapi";
import { authMiddleware } from "./auth";

export const lookup = createRoute({
  method: "get",
  path: "/lookup/{id}",
  request: { query: z.object({ locale: z.string() }) },
  middleware: [authMiddleware],
  responses: {},
});
