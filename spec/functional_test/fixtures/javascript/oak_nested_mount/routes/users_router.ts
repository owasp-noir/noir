import { Router } from "@oak/oak";

const router = new Router();

router.post("/users", (ctx) => {});
router.post("/users/login", (ctx) => {});
router.get("/user", (ctx) => {});

export default router;
