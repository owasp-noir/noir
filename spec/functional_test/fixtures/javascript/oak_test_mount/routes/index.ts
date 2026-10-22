import { Router } from "@oak/oak";
import users from "./users.ts";

const router = new Router();
router.use("/users", users.routes());

export default router;
