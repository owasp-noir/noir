import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { authMiddleware } from "./auth";
const app = new OpenAPIHono();

export const pub = createRoute<"get">({
  method: "get",
  path: "/pub-generic",
  responses: { 200: { description: "ok" } },
});
export const priv = createRoute({
  method: "get",
  path: "/priv",
  middleware: [authMiddleware],
  responses: { 200: { description: "ok" } },
});
const r2 = createRoute
({ method: "get", path: "/pub-newline", responses: {} });
const r3 = createRoute({ method: "get", path: "/priv2", middleware: [authMiddleware], responses: {} });
app.openapi(pub, (c) => c.json({}));
