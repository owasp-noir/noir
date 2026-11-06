require "../../func_spec.cr"

# `createRoute({ middleware: [authMiddleware] })` runs the middleware ahead of
# the handler `app.openapi` registers. Only the object's own `middleware` key
# counts: not a string that mentions one, nor a nested `request` field.
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
    {"/g-open", "/i-tpl", "/l-jsdoc"}.each { |url| guards.call("GET", url).should be_empty }
    {"/f-auth", "/h-auth", "/k-unicode"}.each { |url| guards.call("GET", url).should eq(auth) }

    # generic.ts: `createRoute<"get">({` and a `({` on the next line are read
    # as their own object, never as the next route's.
    guards.call("GET", "/pub-generic").should be_empty
    guards.call("GET", "/pub-newline").should be_empty
    guards.call("GET", "/priv").should eq(auth)
    guards.call("GET", "/priv2").should eq(auth)
  end
end
