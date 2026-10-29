require "../../func_spec.cr"

# #3266: mount prefixes that used to be dropped.
#   err/ - a router imported as `error` is still a router argument.
#   fac/ - a router factory called with arguments, inline or bound first.
#   tpl/ - a template-literal mount path, `process.env.X || 'shop'` read as
#          its literal fallback; the path-mounted handler is reported too.
#   imp/ - a route path built from a constant imported from another module.
#   wrap/ - `withAuth(apiRouter)` is a wrapper around the router, not a factory.
methods = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
expected_endpoints = [
  Endpoint.new("/error/404", "GET"),
  Endpoint.new("/common/layout/404", "GET"),
  Endpoint.new("/shop/:version/list", "GET", [Param.new("version", "", "path")]),
  Endpoint.new("/shop/items", "GET"),
  Endpoint.new("/shop/concat", "GET"),
  Endpoint.new("/local/items", "GET"),
  Endpoint.new("/secure/vault", "GET"),
] of Endpoint
%w[/a /b /c /shop].each do |prefix|
  expected_endpoints << Endpoint.new("#{prefix}/list", "GET", [Param.new("q", "", "query")])
  expected_endpoints << Endpoint.new("#{prefix}/detail", "GET", [Param.new("sid", "", "cookie")])
end
methods.each { |method| expected_endpoints << Endpoint.new("/shop/health_check", method) }

FunctionalTester.new("fixtures/javascript/express_mount_prefix_shapes/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
