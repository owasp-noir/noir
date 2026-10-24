import Koa from "koa";
import Router from "@koa/router";
import documents from "./documents";

const api = new Koa();
const router = new Router();

router.use("/", documents.routes());

api.use(router.routes());
api.use(router.allowedMethods());

export default api;
