import { OpenAPIHono, createRoute, z } from "@hono/zod-openapi";

const getTask = createRoute({
  method: "get",
  path: "/tasks/{id}",
  request: { params: z.object({ id: z.string() }), query: z.object({ verbose: z.string().optional() }) },
  responses: { 200: { description: "ok" } },
});

const app = new OpenAPIHono();
app.openapi(getTask, (c) => c.json({ id: c.req.valid("param").id }));
app.openapi(
  createRoute({ method: "post", path: "/tasks", request: { body: { content: { "application/json": { schema: z.object({ name: z.string() }) } } } }, responses: { 200: { description: "ok" } } }),
  (c) => c.json({}),
);
app.doc("/doc", { openapi: "3.0.0", info: { title: "x", version: "1" } });
app.get("/health", (c) => c.text("ok"));
export default app;
