import { Router } from "@oak/oak";
import users from "./users_router.ts";
import articles from "./articles_router.ts";

// Aggregate sub-routers into `api` (no prefix), then mount `api` under
// /api via the Oak `.routes()` middleware chain.
const api = new Router();
api.use(users.routes());
api.use(articles.routes());

const router = new Router();
router.use("/api", api.routes(), api.allowedMethods());

export default router;
