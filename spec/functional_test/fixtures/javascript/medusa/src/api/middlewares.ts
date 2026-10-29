import { defineMiddlewares, authenticate } from "@medusajs/framework/http"

export default defineMiddlewares({
  routes: [
    {
      matcher: "/store/hello*",
      middlewares: [logRequest()],
    },
    {
      matcher: "/admin/custom*",
      middlewares: [authenticate("user", ["session", "bearer"])],
    },
  ],
})
