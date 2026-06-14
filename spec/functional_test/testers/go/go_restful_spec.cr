require "../../func_spec.cr"

# go-restful (`github.com/emicklei/go-restful`) registers routes as a nested
# builder chain hung off a WebService whose `Path()` supplies the prefix:
#   ws.Path("/users")
#   ws.Route(ws.GET("/{user-id}").To(h).Param(ws.PathParameter("user-id", ...)))
# The full path is the WebService prefix joined with the verb's sub-path, and
# params are self-declared on the chain (PathParameter/QueryParameter/Reads).
expected_endpoints = [
  # GET("/") under Path("/users") keeps the explicit trailing slash.
  Endpoint.new("/users/", "GET"),
  Endpoint.new("/users/{user-id}", "GET", [
    Param.new("user-id", "", "path"),
    Param.new("verbose", "", "query"),
  ]),
  # POST("") registers at the WebService root — no trailing slash — with a
  # JSON body from Reads(User{}).
  Endpoint.new("/users", "POST", [Param.new("body", "", "json")]),
  Endpoint.new("/users/{user-id}", "PUT", [
    Param.new("user-id", "", "path"),
    Param.new("body", "", "json"),
  ]),
  Endpoint.new("/users/{user-id}", "DELETE", [Param.new("user-id", "", "path")]),
  # A second WebService in another file resolves its own Path() prefix.
  Endpoint.new("/api/v1/health/ping", "GET"),
  Endpoint.new("/api/v1/health/ready", "HEAD"),
]

FunctionalTester.new("fixtures/go/go_restful/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests
