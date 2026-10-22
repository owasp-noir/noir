import { Router } from "@oak/oak";

const router = new Router();

router.get("/list", (ctx) => {
  ctx.response.body = [];
});

export default router;
