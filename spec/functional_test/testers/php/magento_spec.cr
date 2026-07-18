require "../../func_spec.cr"

expected_endpoints = [
  # Web API (webapi.xml -> /rest prefix)
  Endpoint.new("/rest/V1/blog/posts", "GET"),
  Endpoint.new("/rest/V1/blog/posts", "POST"),
  Endpoint.new("/rest/V1/blog/posts/{postId}", "GET", [Param.new("postId", "", "path")]),
  Endpoint.new("/rest/V1/blog/posts/{postId}", "DELETE", [Param.new("postId", "", "path")]),

  # MVC controllers (routes.xml frontName + Controller/.../Action.php)
  Endpoint.new("/blog/index/index", "GET"),
  Endpoint.new("/blog/post/view", "GET"),
  Endpoint.new("/blog/post/save", "POST"),
  Endpoint.new("/acme_blog/post/edit", "GET"),
  # Nested Controller/Order/Creditmemo/ collapses to one underscore segment.
  Endpoint.new("/blog/order_creditmemo/save", "POST"),
  # Implements HttpGetActionInterface only; the imported (but unimplemented)
  # HttpPostActionInterface must NOT add POST.
  Endpoint.new("/blog/feed/view", "GET"),
  # Controller/Support/Helper.php has only executeInternal() -> no endpoint.
]

FunctionalTester.new("fixtures/php/magento/", {
  :techs     => 2, # php_magento + php_pure (suppressed in analysis)
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
