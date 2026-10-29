require "../../func_spec.cr"

describe "Vapor shorthand groups, multi-line routes, unresolved paths, and auth groups", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "reports $0 groups, multi-line .on, unresolved segments, and function-scoped auth" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/swift/vapor_routes_auth/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    routes = app.endpoints.map { |endpoint| "#{endpoint.method} #{endpoint.url}" }.sort!
    routes.should eq([
      "GET /:owner/:repo/:ref/{.fragment(.faviconIco)}",
      "GET /:owner/:repo/:ref/{.fragment(.logoPng)}",
      "GET /{SiteURL.faq}",
      "GET /api/packages/:owner/:repository",
      "GET /channels",
      "GET /me",
      "GET /not-in-this-function",
      "GET /previous-only",
      "GET /profile",
      "GET /search",
      "POST /{SiteURL.validate}",
      "POST /notify-inbound-email",
    ])
    routes.should_not contain("GET /")
    routes.should_not contain("POST /")

    guards_of = ->(method : String, url : String) do
      endpoint = app.endpoints.find! { |candidate| candidate.method == method && candidate.url == url }
      endpoint.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("GET", "/search").should_not be_empty
    guards_of.call("GET", "/me").should_not be_empty
    guards_of.call("GET", "/channels").should eq(guards_of.call("GET", "/profile"))
    guards_of.call("GET", "/profile").should_not be_empty
    guards_of.call("GET", "/previous-only").should_not be_empty
    guards_of.call("GET", "/api/packages/:owner/:repository").should be_empty
    guards_of.call("GET", "/not-in-this-function").should be_empty
  end
end
