require "../../func_spec.cr"

# tRPC v11 sub-routers that are not `router(...)` calls:
#   * a plain object (`export const postRouter = { ... } satisfies
#     TRPCRouterRecord`) mounted with `post: postRouter`;
#   * `export default createTRPCRouter({...})` reached through a default
#     import;
#   * a record spread into the root (`...searchProcs`) at the root level.
# `orphanProcs` is a record nothing mounts, so it serves nothing.
expected_endpoints = [
  Endpoint.new("/api/trpc/auth.getSession", "GET"),
  Endpoint.new("/api/trpc/auth.getSecretMessage", "GET"),
  Endpoint.new("/api/trpc/post.all", "GET"),
  Endpoint.new("/api/trpc/post.byId", "GET", [Param.new("id", "", "query")]),
  Endpoint.new("/api/trpc/post.create", "POST", [Param.new("title", "", "body"), Param.new("content", "", "body")]),
  Endpoint.new("/api/trpc/post.delete", "POST", [Param.new("input", "", "body")]),
  Endpoint.new("/api/trpc/health", "GET"),
  Endpoint.new("/api/trpc/search", "GET", [Param.new("q", "", "query")]),
]

FunctionalTester.new("fixtures/typescript/trpc_router_record/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
