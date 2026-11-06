import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { bearerAuth } from "hono/bearer-auth";
import { authMiddleware } from "./auth";
import { rateLimit } from "./limits";

const app = new OpenAPIHono();

app.openapi(
  createRoute({
    method: "post",
    path: "/notes",
    description: "Requires middleware: [authMiddleware] on the caller.",
    middleware: [authMiddleware],
    request: { body: { content: { "application/json": { schema: z.object({ text: z.string() }) } } } },
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

app.openapi(
  createRoute({
    method: "get",
    path: "/notes",
    description: "Public; the middleware: [authMiddleware] text is only a string.",
    request: { query: z.object({ middleware: z.string().optional() }) },
    middleware: [rateLimit()],
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json([]),
);

app.openapi(createRoute({ method: "delete", path: "/notes/{id}", middleware: [bearerAuth({ token: "t" })], responses: { 200: { description: "ok" } } }), (c) => c.json({}));

const purge = createRoute({
  method: "post",
  path: "/purge",
  middleware: [
    rateLimit(),
    authMiddleware,
  ] as const,
  responses: { 200: { description: "ok" } },
});
app.openapi(purge, (c) => c.json({}));

export default app;
