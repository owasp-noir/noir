require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/graphql", "ANY"),
  Endpoint.new("/internal/l7check", "ANY"),
  Endpoint.new("/zipkin/config.json", "ANY"),
  Endpoint.new("/zipkin/api", "ANY"),
  Endpoint.new("/zipkin", "GET"),
  Endpoint.new("/zipkin", "HEAD"),
  Endpoint.new("/favicon.ico", "GET"),
  Endpoint.new("/favicon.ico", "HEAD"),
  Endpoint.new("/", "GET"),
  Endpoint.new("/", "HEAD"),
]

# Create endpoints with path parameters from TestParametersService.java
user_service_endpoint = Endpoint.new("/api/users/{userId}", "ANY")
user_service_endpoint.push_param(Param.new("userId", "", "path"))
expected_endpoints << user_service_endpoint

review_service_endpoint = Endpoint.new("/api/products/{productId}/reviews", "ANY")
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

open_endpoint = Endpoint.new("/open/{openId}", "ANY")
open_endpoint.push_param(Param.new("openId", "", "path"))
expected_endpoints << open_endpoint

bulk_get_endpoint = Endpoint.new("/bulk/{bulkId}", "GET")
bulk_get_endpoint.push_param(Param.new("bulkId", "", "path"))
expected_endpoints << bulk_get_endpoint

bulk_post_endpoint = Endpoint.new("/bulk/{bulkId}", "POST")
bulk_post_endpoint.push_param(Param.new("bulkId", "", "path"))
expected_endpoints << bulk_post_endpoint

insight_put_endpoint = Endpoint.new("/insights/{insightId}", "PUT")
insight_put_endpoint.push_param(Param.new("insightId", "", "path"))
expected_endpoints << insight_put_endpoint

insight_delete_endpoint = Endpoint.new("/insights/{insightId}", "DELETE")
insight_delete_endpoint.push_param(Param.new("insightId", "", "path"))
expected_endpoints << insight_delete_endpoint

wildcard_endpoint = Endpoint.new("/wildcards/{wildcardId}", "ANY")
wildcard_endpoint.push_param(Param.new("wildcardId", "", "path"))
expected_endpoints << wildcard_endpoint

route_builder_get_endpoint = Endpoint.new("/route-builder/{builderId}", "GET")
route_builder_get_endpoint.push_param(Param.new("builderId", "", "path"))
expected_endpoints << route_builder_get_endpoint

route_builder_post_endpoint = Endpoint.new("/route-builder/{builderId}", "POST")
route_builder_post_endpoint.push_param(Param.new("builderId", "", "path"))
expected_endpoints << route_builder_post_endpoint

catalog_get_endpoint = Endpoint.new("/catalog/{catalogId}", "GET")
catalog_get_endpoint.push_param(Param.new("catalogId", "", "path"))
expected_endpoints << catalog_get_endpoint

catalog_status_patch_endpoint = Endpoint.new("/catalog/{catalogId}/status", "PATCH")
catalog_status_patch_endpoint.push_param(Param.new("catalogId", "", "path"))
expected_endpoints << catalog_status_patch_endpoint

prefixed_catalog_get_endpoint = Endpoint.new("/catalog-prefix/catalog/{catalogId}", "GET")
prefixed_catalog_get_endpoint.push_param(Param.new("catalogId", "", "path"))
expected_endpoints << prefixed_catalog_get_endpoint

prefixed_catalog_status_patch_endpoint = Endpoint.new("/catalog-prefix/catalog/{catalogId}/status", "PATCH")
prefixed_catalog_status_patch_endpoint.push_param(Param.new("catalogId", "", "path"))
expected_endpoints << prefixed_catalog_status_patch_endpoint

# Create endpoints from AnnotatedService.java - annotation-based service definitions
# GET /annotated/users with query params: page, limit
annotated_users_get = Endpoint.new("/annotated/users", "GET")
annotated_users_get.push_param(Param.new("page", "", "query"))
annotated_users_get.push_param(Param.new("limit", "25", "query"))
expected_endpoints << annotated_users_get

# GET /annotated/users/{userId} with path param: userId and header: Authorization
annotated_user_get = Endpoint.new("/annotated/users/{userId}", "GET")
annotated_user_get.push_param(Param.new("Authorization", "", "header"))
annotated_user_get.push_param(Param.new("userId", "", "path"))
expected_endpoints << annotated_user_get

# POST /annotated/users with json body fields from User and header: Content-Type
annotated_users_post = Endpoint.new("/annotated/users", "POST")
annotated_users_post.push_param(Param.new("name", "", "json"))
annotated_users_post.push_param(Param.new("email", "", "json"))
annotated_users_post.push_param(Param.new("Content-Type", "", "header"))
expected_endpoints << annotated_users_post

# PUT /annotated/users/{userId} with path param: userId and json body fields from User
annotated_user_put = Endpoint.new("/annotated/users/{userId}", "PUT")
annotated_user_put.push_param(Param.new("name", "", "json"))
annotated_user_put.push_param(Param.new("email", "", "json"))
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

# GET /annotated/files/{*filePath} — rest-path capture binds `filePath`
# as a single path param (no `*filePath`, no spurious query param).
annotated_files_get = Endpoint.new("/annotated/files/{*filePath}", "GET")
annotated_files_get.push_param(Param.new("filePath", "", "path"))
expected_endpoints << annotated_files_get

# OPTIONS /annotated/cors with header: Origin
annotated_cors_options = Endpoint.new("/annotated/cors", "OPTIONS")
annotated_cors_options.push_param(Param.new("Origin", "", "header"))
expected_endpoints << annotated_cors_options

prefixed_report_get = Endpoint.new("/annotated/prefix/reports/{reportId}", "GET")
prefixed_report_get.push_param(Param.new("X-Trace", "", "header"))
prefixed_report_get.push_param(Param.new("reportId", "", "path"))
expected_endpoints << prefixed_report_get

expected_endpoints << Endpoint.new("/annotated/prefix/submit", "POST")
expected_endpoints << Endpoint.new("/annotated/prefix/submit-alt", "POST")

mounted_detail_get = Endpoint.new("/mounted/details/{detailId}", "GET")
mounted_detail_get.push_param(Param.new("detailId", "", "path"))
expected_endpoints << mounted_detail_get

mounted_create_post = Endpoint.new("/mounted/create", "POST")
mounted_create_post.push_param(Param.new("title", "", "json"))
expected_endpoints << mounted_create_post

# DocExampleService.java: only the real builder route is detected.
# The Server.builder() chains inside the Javadoc comment and the Java
# text block (/doc-comment-route, /api/comment-thrift, /doc-textblock-route)
# must NOT surface as endpoints.
expected_endpoints << Endpoint.new("/real/ping", "ANY")

FunctionalTester.new("fixtures/java/armeria/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
