import { Router } from "@oak/oak";
import users from "../routes/users.ts";

Deno.test("mounts users", () => {
  const router = new Router();
  router.use("/oak-test-prefix", users.routes());
});
