require "../../func_spec.cr"

# gitea's `modules/web` wrapper over chi: a suffix registered on a group
# path (`m.Get(".{diffType:diff|patch}", h)`) and `PathGroup` / `MatchPath`
# routes, whose `<name:...>` placeholders read as `{name}`.
expected_endpoints = [
  Endpoint.new("/pulls/{index}", "GET"),
  Endpoint.new("/pulls/{index}.{diffType:diff|patch}", "GET"),
  Endpoint.new("/feed.rss", "GET"),
  Endpoint.new("/commits/{ref}/status", "GET", [Param.new("ref", "", "path")]),
  Endpoint.new("/commits/{ref}/upload/{name}", "POST"),
  Endpoint.new("/commits/{ref}/upload/{name}", "PUT"),
]

FunctionalTester.new("fixtures/go/chi_web_path_group/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
