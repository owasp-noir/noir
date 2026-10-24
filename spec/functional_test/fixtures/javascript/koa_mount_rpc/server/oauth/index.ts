import Koa from "koa";
import Router from "@koa/router";

const app = new Koa();
const router = new Router();

router.post("/register", async (ctx) => {
  ctx.body = { registered: true };
});

app.use(router.routes());

export default app;
