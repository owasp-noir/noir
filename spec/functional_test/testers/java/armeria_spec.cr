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

# Create endpoints from AnnotatedService.java - annotation-based service definitions
# GET /annotated/users with query params: page, limit
annotated_users_get = Endpoint.new("/annotated/users", "GET")
annotated_users_get.push_param(Param.new("page", "", "query"))
annotated_users_get.push_param(Param.new("limit", "", "query"))
expected_endpoints << annotated_users_get

# GET /annotated/users/{userId} with path param: userId and header: Authorization
annotated_user_get = Endpoint.new("/annotated/users/{userId}", "GET")
annotated_user_get.push_param(Param.new("Authorization", "", "header"))
annotated_user_get.push_param(Param.new("userId", "", "path"))
expected_endpoints << annotated_user_get

# POST /annotated/users with json body: user and header: Content-Type
annotated_users_post = Endpoint.new("/annotated/users", "POST")
annotated_users_post.push_param(Param.new("user", "", "json"))
annotated_users_post.push_param(Param.new("Content-Type", "", "header"))
expected_endpoints << annotated_users_post

# PUT /annotated/users/{userId} with path param: userId and json body: user
annotated_user_put = Endpoint.new("/annotated/users/{userId}", "PUT")
annotated_user_put.push_param(Param.new("user", "", "json"))
annotated_user_put.push_param(Param.new("userId", "", "path"))
expected_endpoints << annotated_user_put

# DELETE /annotated/users/{userId} with path param: userId and header: X-Request-Id
annotated_user_delete = Endpoint.new("/annotated/users/{userId}", "DELETE")
annotated_user_delete.push_param(Param.new("X-Request-Id", "", "header"))
annotated_user_delete.push_param(Param.new("userId", "", "path"))
expected_endpoints << annotated_user_delete

# PATCH /annotated/users/{userId}/status with path param: userId and query param: status
annotated_user_status_patch = Endpoint.new("/annotated/users/{userId}/status", "PATCH")
annotated_user_status_patch.push_param(Param.new("status", "", "query"))
annotated_user_status_patch.push_param(Param.new("userId", "", "path"))
expected_endpoints << annotated_user_status_patch

# GET /annotated/search with query params: q, category and header: Accept-Language
annotated_search_get = Endpoint.new("/annotated/search", "GET")
annotated_search_get.push_param(Param.new("q", "", "query"))
annotated_search_get.push_param(Param.new("category", "", "query"))
annotated_search_get.push_param(Param.new("Accept-Language", "", "header"))
expected_endpoints << annotated_search_get

# HEAD /annotated/health (no params)
annotated_health_head = Endpoint.new("/annotated/health", "HEAD")
expected_endpoints << annotated_health_head

# OPTIONS /annotated/cors with header: Origin
annotated_cors_options = Endpoint.new("/annotated/cors", "OPTIONS")
annotated_cors_options.push_param(Param.new("Origin", "", "header"))
expected_endpoints << annotated_cors_options

FunctionalTester.new("fixtures/java/armeria/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
