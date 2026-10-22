import { Application } from "@oak/oak";
import router from "./routes/index.ts";

const app = new Application();
app.use(router.routes());
app.use(router.allowedMethods());

await app.listen({ port: 8000 });
