require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# A guard that wraps a router's handler (`admin.GET("/users",
# withAdminAuth(func(c echo.Context, u User) error {...}))`) is judged by
# its definition, as a net/http wrapper is (see `router_wrap_guards`).
describe "GoAuthTagger router handler wrappers" do
  base = File.expand_path("../../../functional_test/fixtures/go/echo_wrap_auth", __DIR__)

  guards = ->(file : String, line : Int32, url : String, method : String, tech : String) do
    CodeLocator.instance.clear_all
    Dir.glob("#{base}/**/*.go").each { |f| CodeLocator.instance.register_path(f) }
    options = create_test_options
    options["base"] = YAML::Any.new(base)
    details = Details.new(PathInfo.new("#{base}/#{file}", line))
    details.technology = tech
    endpoint = Endpoint.new(url, method, [] of Param, details)
    GoAuthTagger.new(options).perform([endpoint]).first.tags.map(&.description)
  end

  it "reads a wrapper around an Echo closure handler that refuses anonymous callers" do
    guards.call("main.go", 14, "/admin/users", "GET", "go_echo").should eq(["Protected by Go middleware withAdminAuth (verified from its body: refuses anonymous callers)"])
  end

  it "reads each wrapper of a nested chain" do
    guards.call("main.go", 20, "/nested", "GET", "go_echo").should eq(["Protected by Go middleware withAdminAuth (verified from its body: refuses anonymous callers)"])
  end

  it "leaves a logging wrapper, a conversion, a rate limit and a handler factory open" do
    guards.call("main.go", 17, "/logged", "GET", "go_echo").should be_empty
    guards.call("main.go", 18, "/wrapped", "GET", "go_echo").should be_empty
    guards.call("main.go", 19, "/limited", "GET", "go_echo").should be_empty
    guards.call("main.go", 21, "/login", "POST", "go_echo").should be_empty
    guards.call("main.go", 22, "/public", "GET", "go_echo").should be_empty
  end

  it "reads the same wrapper shape on gin and chi" do
    guards.call("routers.go", 12, "/gin/me", "GET", "go_gin").should eq(["Protected by Go middleware ginAuth (verified from its body: refuses anonymous callers)"])
    guards.call("routers.go", 13, "/gin/open", "GET", "go_gin").should be_empty
    guards.call("routers.go", 18, "/chi/me", "GET", "go_chi").should eq(["Protected by Go middleware requireSession (verified from its body: refuses anonymous callers)"])
    guards.call("routers.go", 19, "/chi/raw", "GET", "go_chi").should be_empty
  end
end
