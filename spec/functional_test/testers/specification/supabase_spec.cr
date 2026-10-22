require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/rest/v1/authors", "GET", [
    Param.new("select", "", "query"),
    Param.new("order", "", "query"),
    # Under PostgREST the column name is itself the query key.
    Param.new("name", "string", "query"),
  ]),
  Endpoint.new("/rest/v1/authors", "POST", [
    Param.new("id", "string", "json"),
    Param.new("name", "string", "json"),
    Param.new("email", "string", "json"),
    Param.new("apikey", "", "header"),
    Param.new("Prefer", "", "header"),
  ]),
  Endpoint.new("/rest/v1/authors", "PATCH"),
  Endpoint.new("/rest/v1/authors", "DELETE"),

  Endpoint.new("/rest/v1/posts", "GET"),
  Endpoint.new("/rest/v1/posts", "POST", [
    Param.new("title", "string", "json"),
    # `rating` was renamed to `score` and `body` dropped by the second
    # migration; `slug` was added by it. The generated `search_vector`
    # column is not writable and never appears.
    Param.new("score", "number", "json"),
    Param.new("slug", "string", "json"),
    Param.new("published", "boolean", "json"),
    Param.new("created_at", "datetime", "json"),
  ]),
  Endpoint.new("/rest/v1/posts", "PATCH"),
  Endpoint.new("/rest/v1/posts", "DELETE"),

  # A view is read-only through PostgREST.
  Endpoint.new("/rest/v1/published_posts", "GET"),

  Endpoint.new("/rest/v1/rpc/search_posts", "POST", [
    Param.new("query", "string", "json"),
    Param.new("max_results", "int", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/supabase/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
