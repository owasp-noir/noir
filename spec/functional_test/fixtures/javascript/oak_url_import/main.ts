import { Application, Router } from "https://deno.land/x/oak@v12.6.1/mod.ts";

const router = new Router({ prefix: "/api/v1" });

router.get("/status", (ctx) => {
  ctx.response.body = { status: "ok" };
});

router.get("/items/:itemId", (ctx) => {
  ctx.response.body = { itemId: ctx.params.itemId };
});

const app = new Application();
app.use(router.routes());
app.use(router.allowedMethods());

await app.listen({ port: 8001 });
