import Koa from "koa";
import Router from "@koa/router";
import { renderShare } from "./share";

const koa = new Koa();
const router = new Router();

router.get("/locales/:lng.json", async (ctx) => {
  const { lng } = ctx.params;
  ctx.body = lng;
});

router.get("/s/:shareId", renderShare);
router.get("/s/:shareId/doc/:documentSlug", renderShare);

koa.use(router.routes());

export default koa;
