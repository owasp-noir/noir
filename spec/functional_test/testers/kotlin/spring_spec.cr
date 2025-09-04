require "../../func_spec.cr"

extected_endpoints = [
  Endpoint.new("/api/article/", "GET"),
  Endpoint.new("/api/article/{slug}", "GET", [Param.new("slug", "", "path")]),
  Endpoint.new("/api/user/", "GET"),
  Endpoint.new("/api/user/{login}", "GET", [Param.new("login", "", "path"), Param.new("lorem", "ipsum", "cookie")]),
  Endpoint.new("/v1", "GET", [Param.new("version", "1", "query")]),
  Endpoint.new("/v2", "GET", [Param.new("version", "2", "query")]),
  Endpoint.new("/version2", "GET", [Param.new("version", "2", "query")]),
  Endpoint.new("/v3", "GET", [Param.new("version", "3", "query")]),
  Endpoint.new("/version3", "GET", [Param.new("version", "3", "query")]),
  Endpoint.new("/article", "POST", [
    Param.new("title", "", "json"),
    Param.new("headline", "", "json"),
    Param.new("content", "", "json"),
    Param.new("author", "", "json"),
    Param.new("id", "", "json"),
    Param.new("slug", "", "json"),
    Param.new("addedAt", "", "json"),
    Param.new("deleted", "", "json"),
  ]),
  Endpoint.new("/article2", "POST", [Param.new("title", "", "query"), Param.new("content", "", "query")]),
  Endpoint.new("/article/{slug}", "GET", [Param.new("slug", "", "path"), Param.new("preview", "false", "query")]),
  Endpoint.new("/article/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/article/{id}", "DELETE", [Param.new("id", "", "path"), Param.new("soft", "", "form"), Param.new("X-Custom-Header", "soft-delete", "header")]),
  Endpoint.new("/article2/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/article/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/request", "GET", [Param.new("type", "basic", "query"), Param.new("X-Custom-Header", "basic", "header")]),
  Endpoint.new("/request", "POST", [Param.new("type", "basic", "query"), Param.new("X-Custom-Header", "basic", "header")]),
  Endpoint.new("/request2", "GET", [Param.new("type", "advanced", "query"), Param.new("X-Custom-Header", "advanced", "header")]),
  Endpoint.new("/request2", "POST", [Param.new("type", "advanced", "query"), Param.new("X-Custom-Header", "advanced", "header")]),
]

FunctionalTester.new("fixtures/kotlin/spring/", {
  :techs     => 1,
  :endpoints => extected_endpoints.size,
}, extected_endpoints).perform_tests
