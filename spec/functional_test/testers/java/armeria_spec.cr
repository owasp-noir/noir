require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/graphql", "GET"),
  Endpoint.new("/internal/l7check", "GET"),
  Endpoint.new("/zipkin/config.json", "GET"),
  Endpoint.new("/zipkin/api", "GET"),
  Endpoint.new("/zipkin", "GET"),
  Endpoint.new("/", "GET"),
]

# Create endpoints with path parameters from TestParametersService.java
user_service_endpoint = Endpoint.new("/api/users/{userId}", "GET")
user_service_endpoint.push_param(Param.new("userId", "", "path"))
expected_endpoints << user_service_endpoint

review_service_endpoint = Endpoint.new("/api/products/{productId}/reviews", "GET")
review_service_endpoint.push_param(Param.new("productId", "", "path"))
expected_endpoints << review_service_endpoint

items_endpoint = Endpoint.new("/items/{itemId}", "GET")
items_endpoint.push_param(Param.new("itemId", "", "path"))
expected_endpoints << items_endpoint

orders_endpoint = Endpoint.new("/orders/{orderId}/confirm", "POST")
orders_endpoint.push_param(Param.new("orderId", "", "path"))
expected_endpoints << orders_endpoint

accounts_endpoint = Endpoint.new("/accounts/{accountId}/settings", "PUT")
accounts_endpoint.push_param(Param.new("accountId", "", "path"))
expected_endpoints << accounts_endpoint

comments_endpoint = Endpoint.new("/comments/{commentId}", "DELETE")
comments_endpoint.push_param(Param.new("commentId", "", "path"))
expected_endpoints << comments_endpoint

posts_endpoint = Endpoint.new("/posts/{postId}/status", "PATCH")
posts_endpoint.push_param(Param.new("postId", "", "path"))
expected_endpoints << posts_endpoint

FunctionalTester.new("fixtures/java/armeria/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
