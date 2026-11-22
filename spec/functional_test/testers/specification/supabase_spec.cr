require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/rest/v1/authors", "GET", [
    Param.new("select", "", "query"),
    Param.new("order", "", "query"),
    # Under PostgREST the column name is itself the query key.
    Param.new("name", "string", "query"),
    Param.new("email", "", "query"),
    Param.new("id", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("offset", "", "query"),
  ]),
  Endpoint.new("/rest/v1/authors", "POST", [
    Param.new("id", "string", "json"),
    Param.new("name", "string", "json"),
    Param.new("email", "string", "json"),
    Param.new("apikey", "", "header"),
    Param.new("Prefer", "", "header"),
    Param.new("Authorization", "", "header"),
  ]),
  Endpoint.new("/rest/v1/authors", "PATCH", [
    Param.new("Authorization", "", "header"),
    Param.new("apikey", "", "header"),
    Param.new("Prefer", "", "header"),
    Param.new("email", "", "json"),
    Param.new("id", "", "json"),
    Param.new("name", "", "json"),
    Param.new("email", "", "query"),
    Param.new("id", "", "query"),
    Param.new("name", "", "query"),
  ]),
  Endpoint.new("/rest/v1/authors", "DELETE", [
    Param.new("Authorization", "", "header"),
    Param.new("apikey", "", "header"),
    Param.new("email", "", "query"),
    Param.new("id", "", "query"),
    Param.new("name", "", "query"),
  ]),

  Endpoint.new("/rest/v1/posts", "GET", [
    Param.new("author_id", "", "query"),
    Param.new("created_at", "", "query"),
    Param.new("id", "", "query"),
    Param.new("published", "", "query"),
    Param.new("score", "", "query"),
    Param.new("slug", "", "query"),
    Param.new("title", "", "query"),
    Param.new("limit", "", "query"),
    Param.new("offset", "", "query"),
    Param.new("order", "", "query"),
    Param.new("select", "", "query"),
  ]),
  Endpoint.new("/rest/v1/posts", "POST", [
    Param.new("title", "string", "json"),
    # `rating` was renamed to `score` and `body` dropped by the second
    # migration; `slug` was added by it. The generated `search_vector`
    # column is not writable and never appears.
    Param.new("score", "number", "json"),
    Param.new("slug", "string", "json"),
    Param.new("published", "boolean", "json"),
    Param.new("created_at", "datetime", "json"),
    Param.new("Authorization", "", "header"),
    Param.new("apikey", "", "header"),
    Param.new("Prefer", "", "header"),
    Param.new("author_id", "", "json"),
    Param.new("id", "", "json"),
  ]),
  Endpoint.new("/rest/v1/posts", "PATCH", [
    Param.new("Authorization", "", "header"),
    Param.new("apikey", "", "header"),
    Param.new("Prefer", "", "header"),
    Param.new("author_id", "", "json"),
    Param.new("created_at", "", "json"),
    Param.new("id", "", "json"),
    Param.new("published", "", "json"),
    Param.new("score", "", "json"),
    Param.new("slug", "", "json"),
    Param.new("title", "", "json"),
    Param.new("author_id", "", "query"),
    Param.new("created_at", "", "query"),
    Param.new("id", "", "query"),
    Param.new("published", "", "query"),
    Param.new("score", "", "query"),
    Param.new("slug", "", "query"),
    Param.new("title", "", "query"),
  ]),
  Endpoint.new("/rest/v1/posts", "DELETE", [
    Param.new("Authorization", "", "header"),
    Param.new("apikey", "", "header"),
    Param.new("author_id", "", "query"),
    Param.new("created_at", "", "query"),
    Param.new("id", "", "query"),
    Param.new("published", "", "query"),
    Param.new("score", "", "query"),
    Param.new("slug", "", "query"),
    Param.new("title", "", "query"),
  ]),

  # A view is read-only through PostgREST.
  Endpoint.new("/rest/v1/published_posts", "GET", [
    Param.new("limit", "", "query"),
    Param.new("offset", "", "query"),
    Param.new("order", "", "query"),
    Param.new("select", "", "query"),
  ]),

  Endpoint.new("/rest/v1/rpc/search_posts", "POST", [
    Param.new("query", "string", "json"),
    Param.new("max_results", "int", "json"),
    Param.new("Authorization", "", "header"),
    Param.new("apikey", "", "header"),
  ]),
]

FunctionalTester.new("fixtures/specification/supabase/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
