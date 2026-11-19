require "../../func_spec.cr"

# ASP.NET Core trims an action's `Async` suffix
# (`SuppressAsyncSuffixInActionNames`), unless `[ActionName]` renames it,
# and reads `[Controller]`/`[Action]`/`[Area]` tokens and
# `{Controller=Home}`/`{Action=Index}` placeholders in any case.
expected_endpoints = [
  # async_suffix
  Endpoint.new("/api/Users/GetUsers", "GET"),
  Endpoint.new("/api/Users/CreateUser", "POST", [Param.new("name", "", "json")]),
  Endpoint.new("/api/Users/Lookup", "GET", [Param.new("q", "", "query")]),
  Endpoint.new("/Orders/List", "GET"),
  Endpoint.new("/Orders/Details/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/Orders/Index", "GET"),
  # token_case
  Endpoint.new("/api/Customers", "GET"),
  Endpoint.new("/api/Customers/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/Customers/Import", "POST"),
  Endpoint.new("/Admin/Audit/Index", "GET"),
  Endpoint.new("/api/Orders/Recent", "GET"),
  # placeholder_case
  Endpoint.new("/Home/Index", "GET"),
  Endpoint.new("/Home/Privacy", "GET"),
  Endpoint.new("/Home/Details/{id}", "GET", [Param.new("id", "", "path")]),
]

FunctionalTester.new("fixtures/csharp/aspnet_core_mvc_route_name_case/", {
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
