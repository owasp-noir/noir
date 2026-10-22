import { Application, Router } from "@oak/oak";

const router = new Router();
router.get("/ping", (ctx) => {
  ctx.response.body = "pong";
});

const app = new Application();
app.use(router.routes());
app.use(router.allowedMethods());
await app.listen({ port: 8000 });
