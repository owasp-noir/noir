require "../../func_spec.cr"

describe "Fastify onRequest hooks and route preHandlers", tags: "functional" do
  before_each do
    CodeLocator.instance.clear_all
  end

  it "judges a plugin hook and a route preHandler by what they reply" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/javascript/fastify_hook_guard/")])
    options["ai_context"] = YAML::Any.new(true)
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze
    endpoints = app.endpoints

    guards_of = ->(method : String, url : String) do
      endpoints.find! { |e| e.method == method && e.url == url }.ai_context.try(&.guards.map(&.description)) || [] of String
    end

    guards_of.call("GET", "/api/tasks").join(" ").should contain("onRequest")
    guards_of.call("DELETE", "/api/tasks/:id").join(" ").should contain("onRequest")
    guards_of.call("POST", "/api/auth/login").should be_empty
    guards_of.call("GET", "/public/health").should be_empty
    guards_of.call("GET", "/open").should be_empty
    guards_of.call("GET", "/control").join(" ").should contain("authenticate")
    guards_of.call("GET", "/admin").join(" ").should contain("requireUser")
    guards_of.call("GET", "/inline").join(" ").should contain("preHandler")
    guards_of.call("GET", "/secure").join(" ").should contain("checkToken")
    guards_of.call("GET", "/maybe").should be_empty
    guards_of.call("GET", "/optional").should be_empty
    # A verify call quoted in a string is not one.
    guards_of.call("GET", "/fake").should be_empty
    # A hook that lets routes setting `config.public` through still guards the rest.
    guards_of.call("GET", "/flag/private").join(" ").should contain("onRequest")
    guards_of.call("GET", "/flag/login").should be_empty
    # A hook that gates on config and also refuses every anonymous caller.
    guards_of.call("GET", "/a/plain").join(" ").should contain("onRequest")
    guards_of.call("GET", "/a/joined").join(" ").should contain("onRequest")
    # An exemption joined with another test does not hold for every route.
    guards_of.call("POST", "/b/pubpost").join(" ").should contain("onRequest")
    # A decorator is read in its own package.
    guards_of.call("GET", "/other/secure").should be_empty
  end
end
