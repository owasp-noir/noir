require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/items/posts", "GET", [
    Param.new("fields", "", "query"),
    Param.new("filter", "", "query"),
    Param.new("limit", "", "query"),
    # Bare field names are not Directus query keys - filtering goes
    # through the operator form.
    Param.new("filter[title][_eq]", "", "query"),
  ]),
  Endpoint.new("/items/posts", "POST", [
    Param.new("title", "string", "json"),
    Param.new("views", "int", "json"),
    Param.new("published", "boolean", "json"),
  ]),
  Endpoint.new("/items/posts", "PATCH", [
    Param.new("keys", "array", "json"),
    Param.new("data.title", "string", "json"),
  ]),
  Endpoint.new("/items/posts", "DELETE", [
    Param.new("keys", "array", "json"),
  ]),
  Endpoint.new("/items/posts/{id}", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/items/posts/{id}", "PATCH", [
    Param.new("title", "string", "json"),
  ]),
  Endpoint.new("/items/posts/{id}", "DELETE"),
  # A singleton has one implicit row: no listing, no id segment.
  Endpoint.new("/items/site_settings/singleton", "GET"),
  Endpoint.new("/items/site_settings/singleton", "PATCH", [
    Param.new("site_name", "string", "json"),
  ]),
]

FunctionalTester.new("fixtures/specification/directus/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
