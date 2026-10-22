import { Router } from "@oak/oak";

const router = new Router();

router.get("/articles", (ctx) => {});
router.get("/articles/:slug", (ctx) => {
  const slug = ctx.params.slug;
});

export default router;
