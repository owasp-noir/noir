import { type RouteConfig, route } from "@react-router/dev/routes";
import { flatRoutes } from "@react-router/fs-routes";

export default [
  route("healthz", "health.ts"),
  ...(await flatRoutes()),
] satisfies RouteConfig;
