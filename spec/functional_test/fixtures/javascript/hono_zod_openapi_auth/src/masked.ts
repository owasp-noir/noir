import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";
import { cors } from "hono/cors";
import { logger } from "hono/logger";
import { zValidator } from "@hono/zod-validator";
import { authMiddleware } from "./auth";

const app = new OpenAPIHono();

// A: auth middleware commented out with a block comment -> OPEN
app.openapi(
  createRoute({
    method: "post",
    path: "/a-blockcomment",
    /*
    middleware: [authMiddleware],
    */
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

// B: multi-line template description mentions middleware -> OPEN
app.openapi(
  createRoute({
    method: "post",
    path: "/b-template",
    description: `Deletes it.
middleware: [authMiddleware] is planned`,
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

// C: non-auth middleware -> OPEN
app.openapi(
  createRoute({
    method: "post",
    path: "/c-nonauth",
    middleware: [cors(), logger(), zValidator("json", z.object({}))],
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

// D: nested middleware in responses -> OPEN
app.openapi(
  createRoute({
    method: "post",
    path: "/d-nested",
    responses: { 200: { description: "ok", middleware: [authMiddleware] } },
  }),
  (c) => c.json({}),
);

// E: createRoute(config) with variable, next route has auth -> E OPEN, F GUARDED
const cfg = { method: "get", path: "/e-var", responses: {} } as const;
app.openapi(createRoute(cfg), (c) => c.json({}));
app.openapi(
  createRoute({
    method: "get",
    path: "/f-auth",
    middleware: [authMiddleware],
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

// G: two routes, only second has middleware -> G OPEN
const g = createRoute({
  method: "get",
  path: "/g-open",
  responses: { 200: { description: "ok" } },
});
const h = createRoute({
  method: "get",
  path: "/h-auth",
  middleware: authMiddleware,
  responses: { 200: { description: "ok" } },
});
app.openapi(g, (c) => c.json({}));
app.openapi(h, (c) => c.json({}));

// I: template string single line with middleware: and braces -> OPEN
app.openapi(createRoute({ method: "get", path: "/i-tpl", summary: `x ${"{"} middleware: [authMiddleware]`, responses: {} }), (c) => c.json({}));

// J: regex with brace in request, real auth middleware after -> GUARDED (main FN is fine)
app.openapi(
  createRoute({
    method: "get",
    path: "/j-regex/{id}",
    request: { params: z.object({ id: z.string().regex(/^[^}]+$/) }) },
    middleware: [authMiddleware],
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

// K: unicode before key -> GUARDED
app.openapi(
  createRoute({
    method: "get",
    path: "/k-unicode",
    summary: "한글 설명 😀 {",
    middleware: [authMiddleware],
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

// L: JSDoc-style comment block inside -> OPEN
app.openapi(
  createRoute({
    method: "get",
    path: "/l-jsdoc",
    /**
     * TODO: middleware: [authMiddleware]
     */
    responses: { 200: { description: "ok" } },
  }),
  (c) => c.json({}),
);

export default app;
