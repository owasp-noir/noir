require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/", "GET"),
  Endpoint.new("/about", "GET"),
  # `users/[id].tsx` exports a default component (GET via page) plus
  # a handler with explicit GET / PUT / DELETE. The component-driven
  # GET overlaps with the handler GET and dedupes inside the
  # analyzer's `verbs.uniq`.
  Endpoint.new("/users/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "PUT", [Param.new("id", "", "path")]),
  Endpoint.new("/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/users", "GET"),
  Endpoint.new("/api/users", "POST"),
  # Single-function handler — fans out to GET / POST / PUT / DELETE / PATCH.
  Endpoint.new("/api/health", "GET"),
  Endpoint.new("/api/health", "POST"),
  Endpoint.new("/api/health", "PUT"),
  Endpoint.new("/api/health", "DELETE"),
  Endpoint.new("/api/health", "PATCH"),
  Endpoint.new("/{slug}", "GET", [Param.new("slug", "", "path")]),
]

tester = FunctionalTester.new("fixtures/javascript/fresh/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reports each handler member's line", tags: "functional" do
  user = ->(method : String) { tester.endpoints.find! { |endpoint| endpoint.url == "/users/{id}" && endpoint.method == method } }
  user.call("GET").details.code_paths.first.line.should eq(4)
  user.call("DELETE").details.code_paths.first.line.should eq(10)
end
