import Koa from "koa";
import mount from "koa-mount";
import api from "./api";
import oauth from "./oauth";
import routes from "./routes";

const app = new Koa();
app.use(mount("/api", api));
app.use(mount("/oauth", oauth));
app.use(mount(routes));

export default app;
