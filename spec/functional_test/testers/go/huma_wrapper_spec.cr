require "../../func_spec.cr"

# vikunja registers every /api/v2 operation through its own generic
# `Register(api, huma.Operation{...}, handler)` wrapper, under the base path
# its OpenAPI server declares (`huma.Server{URL: GroupPrefix}`), with the
# API's default `Security` and per-operation opt-outs.
update_params = [Param.new("id", "", "path"), Param.new("format", "", "query"), Param.new("title", "", "json")]
expected_endpoints = [
  Endpoint.new("/api/v2/labels/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("expand", "", "query"),
  ]),
  # An inline `in *struct {…}` input supplies path, query and body params.
  Endpoint.new("/api/v2/labels/{id}", "PUT", update_params),
  # Synthesised by `autopatch.AutoPatch` from the GET + PUT pair.
  Endpoint.new("/api/v2/labels/{id}", "PATCH", update_params),
  Endpoint.new("/api/v2/login", "POST"),
  Endpoint.new("/api/v2/info", "GET"),
  Endpoint.new("/api/v2/feed.atom", "GET"),
  Endpoint.new("/api/v2/health", "GET"),
  # Registered through a wrapper of the wrapper.
  Endpoint.new("/api/v2/gated", "GET", [Param.new("id", "", "path")]),
  # A group's prefix is added under the server base path.
  Endpoint.new("/api/v2/admin/users/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/items/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/items/{id}", "PUT", update_params),
  Endpoint.new("/api/v2/items/{id}", "PATCH", update_params),
  # No PATCH: `"autopatch": false` metadata, and a PUT without a body.
  Endpoint.new("/api/v2/nopatch/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/nopatch/{id}", "PUT", update_params),
  Endpoint.new("/api/v2/nobody/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/nobody/{id}", "PUT", [Param.new("id", "", "path")]),
]

tester = FunctionalTester.new("fixtures/go/huma_wrapper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the handler and reads the declared operation security", tags: "functional" do
  api_go = "./spec/functional_test/fixtures/go/huma_wrapper/api/api.go"
  by_key = tester.app.endpoints.to_h { |ep| {"#{ep.method} #{ep.url}", ep} }
  by_key["GET /api/v2/labels/{id}"].handler.should eq(Handler.new("labelsRead", api_go, 79))
  access = ->(key : String) { by_key[key].tags.select(&.tagger.==("go_huma_access")).map(&.name) }
  # The API's default security, inherited.
  access.call("GET /api/v2/labels/{id}").should eq ["auth"]
  by_key["GET /api/v2/labels/{id}"].tags.find!(&.name.==("auth")).description.should contain("JWTKeyAuth or APITokenAuth")
  # `Security: publicSecurity` (a package variable) and an inline empty list.
  access.call("POST /api/v2/login").should eq ["anonymous"]
  access.call("GET /api/v2/info").should eq ["anonymous"]
  # Its own requirement replaces the default.
  access.call("GET /api/v2/feed.atom").should eq ["auth"]
  by_key["GET /api/v2/feed.atom"].tags.find!(&.name.==("auth")).description.should contain("BasicAuth")
  # A sugar call's modifier, and a group's: each sets that operation's
  # security, and neither is the API's default.
  access.call("GET /api/v2/health").should eq ["anonymous"]
  by_key["DELETE /api/v2/admin/users/{id}"].tags.find!(&.name.==("auth")).description.should contain("AdminKey")
  access.call("GET /api/v2/items/{id}").should eq ["auth"]
end
