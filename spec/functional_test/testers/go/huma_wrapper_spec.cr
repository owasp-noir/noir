require "../../func_spec.cr"
require "file_utils"

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
  Endpoint.new("/api/v2/signup", "POST", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/filled/own", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/filled/unset", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/open/sub/x", "GET", [Param.new("id", "", "path")]),
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
  # A wrapper's own `op.Security = …`; a modifier filling in only a missing
  # one; a parent group's modifier reaching a child group's operations.
  access.call("POST /api/v2/signup").should eq ["anonymous"]
  access.call("GET /api/v2/filled/own").should eq ["anonymous"]
  by_key["GET /api/v2/filled/unset"].tags.find!(&.name.==("auth")).description.should contain("AdminKey")
  access.call("GET /api/v2/open/sub/x").should eq ["anonymous"]
  # Read like OpenAPI `security`: either alternative's credential.
  Access.of(by_key["GET /api/v2/labels/{id}"]).map(&.to_s).should eq ["authenticated"]
  Access.of(by_key["POST /api/v2/login"]).map(&.to_s).should eq ["anonymous"]
end

it "reads Huma operation security schemes and scopes like OpenAPI", tags: "functional" do
  dir = File.tempname("huma_security")
  Dir.mkdir_p(dir)
  File.write(File.join(dir, "go.mod"), "module example.com/h\n\nrequire github.com/danielgtaylor/huma/v2 v2.19.0\n")
  File.write(File.join(dir, "main.go"), <<-GO)
    package main

    import (
    	"context"

    	"github.com/danielgtaylor/huma/v2"
    )

    type Out struct{}

    func h(ctx context.Context, in *struct{}) (*Out, error) { return nil, nil }

    func routes(api huma.API, scopes []string) {
    	huma.Register(api, huma.Operation{Method: "GET", Path: "/scoped", Security: []map[string][]string{{"oauth": {"read", "write"}}, {"key": {}}}}, h)
    	huma.Register(api, huma.Operation{Method: "GET", Path: "/both", Security: []map[string][]string{{"a": {}, "b": {}}}}, h)
    	huma.Register(api, huma.Operation{Method: "GET", Path: "/var", Security: []map[string][]string{{"oauth": scopes}}}, h)
    }
    GO
  begin
    CodeLocator.instance.clear_all
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new(dir)])
    options["nolog"] = YAML::Any.new(true)
    app = NoirRunner.new(options)
    app.detect
    app.analyze
    reading = ->(url : String) { Access.of(app.endpoints.find! { |ep| ep.url == url }).map(&.to_s) }
    # The scheme registry is not read, so the scopes stay unread; the key
    # alternative still admits any caller holding a credential.
    reading.call("/scoped").should eq ["authenticated", "(authenticated | unresolved)"]
    reading.call("/both").should eq ["authenticated"]
    reading.call("/var").should eq ["authenticated", "unresolved"]
    Access.of(app.endpoints.find! { |ep| ep.url == "/var" }).last.any_of.first.value.should eq "oauth: scopes"
  ensure
    FileUtils.rm_rf(dir)
  end
end
