import {
  type RouteConfig,
  index,
  layout,
  prefix,
  route,
} from "@react-router/dev/routes";

export default [
  index("routes/home.tsx"),
  route("about", "routes/about.tsx"),
  layout("routes/auth/layout.tsx", [
    route("login", "routes/auth/login.tsx"),
  ]),
  ...prefix("api", [
    route("users", "routes/api/users.ts"),
    route("users/:id", "routes/api/user.ts"),
  ]),
  route("docs/*", "routes/docs.tsx"),
  route(":lang?/blog", "routes/blog.tsx"),
] satisfies RouteConfig;
