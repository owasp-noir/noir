import { Application, Router } from "@oak/oak";

const router = new Router();

router.get("/users", (ctx) => {
  ctx.response.body = { users: [] };
});

router.post("/users", async (ctx) => {
  const { name, email } = await ctx.request.body.json();
  ctx.response.body = { name, email };
});

router.get("/users/:id", (ctx) => {
  ctx.response.body = { id: ctx.params.id };
});

router.put("/users/:id", async (ctx) => {
  const { name } = await ctx.request.body.json();
  ctx.response.body = { id: ctx.params.id, name };
});

router.delete("/users/:id", (ctx) => {
  ctx.response.status = 204;
});

router.get("/search", (ctx) => {
  const q = ctx.request.url.searchParams.get("q");
  ctx.response.body = { q };
});

router.get("/profile", async (ctx) => {
  const token = ctx.request.headers.get("x-api-key");
  const session = await ctx.cookies.get("session");
  ctx.response.body = { token, session };
});

const app = new Application();
app.use(router.routes());
app.use(router.allowedMethods());

await app.listen({ port: 8000 });
