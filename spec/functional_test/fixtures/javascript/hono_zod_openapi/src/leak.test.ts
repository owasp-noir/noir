import { OpenAPIHono, createRoute } from "@hono/zod-openapi";

const leak = createRoute({
  method: "get",
  path: "/leak",
  responses: { 200: { description: "ok" } },
});
const app = new OpenAPIHono();
app.openapi(leak, (c) => c.json({}));
app.doc("/leak-doc");
