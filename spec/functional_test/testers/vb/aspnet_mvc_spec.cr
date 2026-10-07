require "../../func_spec.cr"

expected_endpoints = [
  # RouteConfig.vb: a literal MapRoute; the `{Controller}/{Action}/{id}`
  # template expands the MVC controllers below instead of being emitted, and
  # the Admin area's `Admin/{controller}/...` template does not replace it.
  Endpoint.new("/about-us", "GET"),

  # MVC 5 conventional routing.
  Endpoint.new("/Home/Index", "GET"),
  Endpoint.new("/Home/Details/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Home/Contact", "POST", [
    Param.new("name", "", "form"),
    Param.new("message", "", "form"),
  ]),
  Endpoint.new("/Home/Search", "GET", [Param.new("query", "", "query")]),
  Endpoint.new("/Home/Search", "POST", [Param.new("query", "", "form")]),
  Endpoint.new("/Home/Delete/{id}", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/Home/About", "GET"),

  # ASP.NET Core attribute routing with `[controller]` / `[action]` tokens.
  Endpoint.new("/api/Products", "GET", [Param.new("category", "", "query")]),
  Endpoint.new("/api/Products/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Products", "POST", [
    Param.new("product", "", "json"),
    Param.new("X-Api-Key", "", "header"),
  ]),
  Endpoint.new("/api/Products/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Products/Export", "GET"),

  # Web API 2 attribute routing under `<RoutePrefix>`.
  Endpoint.new("/api/users", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users", "POST", [Param.new("user", "", "json")]),
  Endpoint.new("/api/users/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("user", "", "json"),
  ]),
  Endpoint.new("/api/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/users/search", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/api/Users", "GET"),

  # Web API 2 conventional routing through `MapHttpRoute`.
  Endpoint.new("/api/Values", "GET"),
  Endpoint.new("/api/Values/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Values", "POST", [Param.new("value", "", "json")]),
  Endpoint.new("/api/Values/{id}", "PUT", [
    Param.new("id", "", "path"),
    Param.new("value", "", "json"),
  ]),
  Endpoint.new("/api/Values/{id}", "DELETE", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/vb/aspnet_mvc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
