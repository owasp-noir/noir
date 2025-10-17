require "../../func_spec.cr"

extected_endpoints = [
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
extected_endpoints << user_service_endpoint

review_service_endpoint = Endpoint.new("/api/products/{productId}/reviews", "GET")
review_service_endpoint.push_param(Param.new("productId", "", "path"))
extected_endpoints << review_service_endpoint

items_endpoint = Endpoint.new("/items/{itemId}", "GET")
items_endpoint.push_param(Param.new("itemId", "", "path"))
extected_endpoints << items_endpoint

orders_endpoint = Endpoint.new("/orders/{orderId}/confirm", "POST")
orders_endpoint.push_param(Param.new("orderId", "", "path"))
extected_endpoints << orders_endpoint

accounts_endpoint = Endpoint.new("/accounts/{accountId}/settings", "PUT")
accounts_endpoint.push_param(Param.new("accountId", "", "path"))
extected_endpoints << accounts_endpoint

comments_endpoint = Endpoint.new("/comments/{commentId}", "DELETE")
comments_endpoint.push_param(Param.new("commentId", "", "path"))
extected_endpoints << comments_endpoint

posts_endpoint = Endpoint.new("/posts/{postId}/status", "PATCH")
posts_endpoint.push_param(Param.new("postId", "", "path"))
extected_endpoints << posts_endpoint

FunctionalTester.new("fixtures/java/armeria/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
