import Router from "@koa/router";
import auth from "@server/middlewares/authentication";
import { rateLimiter } from "../../middlewares/rateLimiter";

const router = new Router();

router.post(
  "documents.info",
  auth({ optional: true }),
  async (ctx) => {
    const { id } = ctx.request.body;
    ctx.body = { id };
  }
);

router.post(
  "documents.create",
  auth(),
  rateLimiter(),
  async (ctx) => {
    const { title } = ctx.request.body;
    ctx.body = { title };
  }
);

router.post("auth.config", async (ctx) => {
  ctx.body = { ok: true };
});

export default router;
