require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# `re_path(r"^media/(?P<path>.*)$", serve)`: a named group whose pattern is
# `.*` / `.+` matches across `/`, so it is the rest of the path. Reported as
# the one-segment `{path}`, `noir trace "GET /media/css/site.css"` found no
# route. A group with a character class stays one segment.
expected_endpoints = [
  Endpoint.new("/media/{*path}", "GET", [Param.new("path", "", "path")]),
  Endpoint.new("/docs/{*page}/", "GET", [Param.new("page", "", "path")]),
  Endpoint.new("/users/{username}/", "GET", [Param.new("username", "", "path")]),
]

tester = FunctionalTester.new("fixtures/python/django_regex_rest_path/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Django re_path rest-of-path groups", tags: "functional" do
  it "traces a nested request path to the route" do
    endpoints = tester.app.endpoints
    Noir::CLI::Inspect.trace(endpoints, "GET", "/media/css/site.css").map { |m| {m.endpoint.url, m.matched_by} }.should eq([{"/media/{*path}", "wildcard"}])
    Noir::CLI::Inspect.trace(endpoints, "GET", "/users/a/b/").should be_empty
  end
end
