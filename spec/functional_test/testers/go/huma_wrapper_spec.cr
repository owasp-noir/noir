require "../../func_spec.cr"

# vikunja registers every /api/v2 operation through its own generic
# `Register(api, huma.Operation{...}, handler)` wrapper, under the base path
# its OpenAPI server declares (`huma.Server{URL: GroupPrefix}`), with the
# API's default `Security` and per-operation opt-outs.
expected_endpoints = [
  Endpoint.new("/api/v2/labels/{id}", "GET", [
    Param.new("id", "", "path"),
    Param.new("expand", "", "query"),
  ]),
  Endpoint.new("/api/v2/labels/{id}", "PUT", [Param.new("id", "", "path")]),
  # Synthesised by `autopatch.AutoPatch` from the GET + PUT pair.
  Endpoint.new("/api/v2/labels/{id}", "PATCH", [Param.new("id", "", "path")]),
  Endpoint.new("/api/v2/login", "POST"),
  Endpoint.new("/api/v2/info", "GET"),
  Endpoint.new("/api/v2/feed.atom", "GET"),
]

tester = FunctionalTester.new("fixtures/go/huma_wrapper/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "names the handler and reads the declared operation security", tags: "functional" do
  api_go = "./spec/functional_test/fixtures/go/huma_wrapper/api/api.go"
  by_url = tester.app.endpoints.select(&.method.in?("GET", "POST")).to_h { |ep| {ep.url, ep} }
  by_url["/api/v2/labels/{id}"].handler.should eq(Handler.new("labelsRead", api_go, 79))
  access = ->(url : String) { by_url[url].tags.select(&.tagger.==("go_huma_access")).map(&.name) }
  # The API's default security, inherited.
  access.call("/api/v2/labels/{id}").should eq ["auth"]
  by_url["/api/v2/labels/{id}"].tags.find!(&.name.==("auth")).description.should contain("JWTKeyAuth or APITokenAuth")
  # `Security: publicSecurity` (a package variable) and an inline empty list.
  access.call("/api/v2/login").should eq ["anonymous"]
  access.call("/api/v2/info").should eq ["anonymous"]
  # Its own requirement replaces the default.
  access.call("/api/v2/feed.atom").should eq ["auth"]
  by_url["/api/v2/feed.atom"].tags.find!(&.name.==("auth")).description.should contain("BasicAuth")
end
