require "../../func_spec.cr"

# Appwrite <=1.5 vocabulary: collections/documents under /v1/databases.
collection_endpoints = [
  Endpoint.new("/v1/databases/blog/collections/posts/documents", "GET", [
    Param.new("queries", "", "query"),
    Param.new("search", "", "query"),
    Param.new("X-Appwrite-Project", "noir_demo", "header"),
  ]),
  Endpoint.new("/v1/databases/blog/collections/posts/documents", "POST", [
    Param.new("documentId", "", "json"),
    Param.new("data.title", "string", "json"),
    Param.new("data.views", "int", "json"),
    Param.new("data.published", "boolean", "json"),
    Param.new("data.tags", "array", "json"),
    Param.new("permissions", "array", "json"),
  ]),
  Endpoint.new("/v1/databases/blog/collections/posts/documents/{documentId}", "GET", [
    Param.new("documentId", "", "path"),
  ]),
  Endpoint.new("/v1/databases/blog/collections/posts/documents/{documentId}", "PATCH", [
    Param.new("data.title", "string", "json"),
  ]),
  Endpoint.new("/v1/databases/blog/collections/posts/documents/{documentId}", "DELETE"),
  Endpoint.new("/v1/functions/sendNewsletter/executions", "POST", [
    Param.new("body", "string", "json"),
    Param.new("async", "boolean", "json"),
  ]),
  Endpoint.new("/v1/functions/sendNewsletter/executions", "GET"),
  Endpoint.new("/v1/functions/sendNewsletter/executions/{executionId}", "GET"),
  Endpoint.new("/v1/storage/buckets/avatars/files", "GET"),
  Endpoint.new("/v1/storage/buckets/avatars/files", "POST", [
    Param.new("fileId", "string", "form"),
    Param.new("file", "string", "form"),
  ]),
  Endpoint.new("/v1/storage/buckets/avatars/files/{fileId}", "GET"),
  Endpoint.new("/v1/storage/buckets/avatars/files/{fileId}", "DELETE"),
  Endpoint.new("/v1/storage/buckets/avatars/files/{fileId}/download", "GET"),
]

FunctionalTester.new("fixtures/specification/appwrite/", {
  :techs     => 1,
  :endpoints => collection_endpoints.size,
}, collection_endpoints).perform_tests

# Appwrite >=1.6 renamed collections/documents to tables/rows and moved
# the mount to /v1/tablesdb. A project speaks one dialect or the other.
table_endpoints = [
  Endpoint.new("/v1/tablesdb/shop/tables/orders/rows", "GET"),
  Endpoint.new("/v1/tablesdb/shop/tables/orders/rows", "POST", [
    Param.new("rowId", "", "json"),
    Param.new("data.sku", "string", "json"),
    Param.new("data.quantity", "int", "json"),
  ]),
  Endpoint.new("/v1/tablesdb/shop/tables/orders/rows/{rowId}", "GET", [
    Param.new("rowId", "", "path"),
  ]),
  Endpoint.new("/v1/tablesdb/shop/tables/orders/rows/{rowId}", "PATCH"),
  Endpoint.new("/v1/tablesdb/shop/tables/orders/rows/{rowId}", "DELETE"),
]

FunctionalTester.new("fixtures/specification/appwrite_tables/", {
  :techs     => 1,
  :endpoints => table_endpoints.size,
}, table_endpoints).perform_tests
