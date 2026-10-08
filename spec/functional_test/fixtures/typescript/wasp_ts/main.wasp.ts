import { app, page, route } from "@wasp.sh/spec";

import { MainPage } from "./src/MainPage" with { type: "ref" };
import { authConfig, authSpec } from "./src/features/auth/auth.wasp";
import { tasksSpec } from "./src/features/tasks/tasks.wasp";

export default app({
  name: "TodoApp",
  wasp: { version: "^0.26.0" },
  title: "Todo",
  auth: authConfig,
  spec: [
    route("RootRoute", "/", page(MainPage)),
    authSpec,
    tasksSpec,
  ],
});
