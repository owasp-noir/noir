require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/api/trpc/user.list", "GET", [] of Param),
  Endpoint.new("/api/trpc/user.byId", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/api/trpc/user.create", "POST", [
    Param.new("name", "", "body"),
    Param.new("email", "", "body"),
  ]),
  Endpoint.new("/api/trpc/post.list", "GET", [] of Param),
  Endpoint.new("/api/trpc/post.byId", "GET", [
    Param.new("postId", "", "query"),
  ]),
  Endpoint.new("/api/trpc/post.liveFeed", "SUBSCRIBE", [] of Param),
  Endpoint.new("/api/trpc/account.me", "GET", [] of Param),
  Endpoint.new("/api/trpc/account.update", "POST", [
    Param.new("displayName", "", "body"),
  ]),
  Endpoint.new("/api/trpc/health", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/trpc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
