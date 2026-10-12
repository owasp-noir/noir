import { createApp } from "honox/factory";

// `createApp()` from `honox/factory` returns a Hono app, so HonoX mounts it
// at the module's path just like `new Hono()`.
const app = createApp();

app.get("/list", (c) => c.json([]));

export default app;
