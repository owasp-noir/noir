require "../../func_spec.cr"

# `createRoute({ middleware: [authMiddleware] })` runs the middleware ahead of
# the handler `app.openapi` registers. Only the object's own `middleware` key
# counts: not a string that mentions one, nor a nested `request` field.
expected_endpoints = [
  Endpoint.new("/events", "GET"),
  Endpoint.new("/news", "GET"),
  Endpoint.new("/notes", "POST", [Param.new("text", "", "json")]),
  Endpoint.new("/notes", "GET", [Param.new("middleware", "", "query")]),
  Endpoint.new("/notes/{id}", "DELETE", [Param.new("id", "", "path")]),
  Endpoint.new("/j-regex/{id}", "GET", [Param.new("id", "", "path")]),
  Endpoint.new("/lookup/{id}", "GET", [Param.new("id", "", "path"), Param.new("locale", "", "query")]),
]
%w[/priv /v1/priv /preview/priv].each do |path|
  expected_endpoints << Endpoint.new(path, "GET", [Param.new("page", "", "query")])
end
%w[/purge /team/purge /a-blockcomment /b-template /c-nonauth /d-nested].each do |path|
  expected_endpoints << Endpoint.new(path, "POST")
end
%w[/e-var /f-auth /g-open /h-auth /i-tpl /k-unicode /l-jsdoc /pub-generic /pub-newline].each do |path|
  expected_endpoints << Endpoint.new(path, "GET")
end

FunctionalTester.new("fixtures/javascript/hono_zod_openapi_auth/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "Hono zod-openapi createRoute middleware", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "guards routes whose createRoute lists an auth middleware" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/hono_zod_openapi_auth/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    guards = ->(method : String, url : String) do
      endpoint = app.endpoints.find { |item| item.method == method && item.url == url }
      fail("missing #{method} #{url}; have #{app.endpoints.map { |item| "#{item.method} #{item.url}" }}") unless endpoint
      (endpoint.ai_context.try(&.guards.compact_map(&.description)) || [] of String).select(&.starts_with?("Protected by Hono"))
    end

    guards.call("POST", "/notes").should eq(["Protected by Hono authMiddleware middleware"])
    guards.call("GET", "/notes").should be_empty
    guards.call("DELETE", "/notes/{id}").should eq(["Protected by Hono bearerAuth middleware"])
    guards.call("POST", "/purge").should eq(["Protected by Hono authMiddleware middleware"])

    # masked.ts: a middleware only a comment, a template literal or a nested
    # object mentions is no guard; a regex or non-ASCII text before a real one
    # does not hide it.
    auth = ["Protected by Hono authMiddleware middleware"]
    {"/a-blockcomment", "/b-template", "/c-nonauth", "/d-nested"}.each { |url| guards.call("POST", url).should be_empty }
    {"/e-var", "/g-open", "/i-tpl", "/l-jsdoc"}.each { |url| guards.call("GET", url).should be_empty }
    {"/f-auth", "/h-auth", "/j-regex/{id}", "/k-unicode"}.each { |url| guards.call("GET", url).should eq(auth) }

    # generic.ts: `createRoute<"get">({` and a `({` on the next line are read
    # as their own object, never as the next route's.
    guards.call("GET", "/pub-generic").should be_empty
    guards.call("GET", "/pub-newline").should be_empty
    guards.call("GET", "/priv").should eq(auth)
    guards.call("GET", "/v1/priv").should eq(auth)
    guards.call("GET", "/preview/priv").should eq(auth)
    guards.call("POST", "/team/purge").should eq(auth)
    app.endpoints.any? { |ep| ep.url == "/priv2" }.should be_false
    guards.call("GET", "/lookup/{id}").should be_empty
    app.endpoints.select(&.resolution.try(&.has_key?("registration"))).map { |ep| {ep.url, ep.resolution} }.should eq([
      {"/lookup/{id}", {"registration" => Endpoint::RESOLUTION_UNRESOLVED}},
    ])
  end
end
