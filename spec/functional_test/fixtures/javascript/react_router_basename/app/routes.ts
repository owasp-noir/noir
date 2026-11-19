import { type RouteConfig, index, route } from "@react-router/dev/routes";
export default [
  index("routes/home.tsx"),
  route("api/users", "routes/api-users.ts"),
] satisfies RouteConfig;
