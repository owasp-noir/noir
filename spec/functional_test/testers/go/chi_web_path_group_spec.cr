require "../../func_spec.cr"

# gitea's `modules/web` wrapper over chi: a suffix registered on a group
# path (`m.Get(".{diffType:diff|patch}", h)`) and `PathGroup` / `MatchPath`
# routes, whose `<name:...>` placeholders read as `{name}`.
expected_endpoints = [
  Endpoint.new("/pulls/{index}", "GET", [Param.new("index", "", "path")]),
  Endpoint.new("/pulls/{index}.{diffType:diff|patch}", "GET", [Param.new("diffType", "", "path"), Param.new("index", "", "path")]),
  Endpoint.new("/feed.rss", "GET"),
  Endpoint.new("/commits/{ref}/status", "GET", [Param.new("ref", "", "path")]),
  Endpoint.new("/commits/{ref}/upload/{name}", "POST", [Param.new("name", "", "path"), Param.new("ref", "", "path")]),
  Endpoint.new("/commits/{ref}/upload/{name}", "PUT", [Param.new("name", "", "path"), Param.new("ref", "", "path")]),
]

FunctionalTester.new("fixtures/go/chi_web_path_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
