require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# A guard that wraps a router's handler (`admin.GET("/users",
# withAdminAuth(func(c echo.Context, u User) error {...}))`) is judged by
# its definition, as a net/http wrapper is (see `router_wrap_guards`).
describe "GoAuthTagger router handler wrappers" do
  fixtures = File.expand_path("../../../functional_test/fixtures/go", __DIR__)

  guards = ->(fixture : String, file : String, line : Int32, url : String, method : String, tech : String) do
    base = "#{fixtures}/#{fixture}"
    CodeLocator.instance.clear_all
    Dir.glob("#{base}/**/*.go").each { |f| CodeLocator.instance.register_path(f) }
    options = create_test_options
    options["base"] = YAML::Any.new(base)
    details = Details.new(PathInfo.new("#{base}/#{file}", line))
    details.technology = tech
    endpoint = Endpoint.new(url, method, [] of Param, details)
    GoAuthTagger.new(options).perform([endpoint]).first.tags.map(&.description)
  end
  wrapped = ->(file : String, line : Int32, url : String, method : String, tech : String) do
    guards.call("echo_wrap_auth", file, line, url, method, tech)
  end
  cases = ->(line : Int32, url : String, method : String) do
    guards.call("echo_wrap_auth_cases", "main.go", line, url, method, "go_echo")
  end

  it "reads a wrapper around an Echo closure handler that refuses anonymous callers" do
    wrapped.call("main.go", 14, "/admin/users", "GET", "go_echo").should eq(["Protected by Go middleware withAdminAuth (verified from its body: refuses anonymous callers)"])
  end

  it "reads each wrapper of a nested chain" do
    wrapped.call("main.go", 20, "/nested", "GET", "go_echo").should eq(["Protected by Go middleware withAdminAuth (verified from its body: refuses anonymous callers)"])
  end

  it "leaves a logging wrapper, a conversion, a rate limit and a handler factory open" do
    wrapped.call("main.go", 17, "/logged", "GET", "go_echo").should be_empty
    wrapped.call("main.go", 18, "/wrapped", "GET", "go_echo").should be_empty
    wrapped.call("main.go", 19, "/limited", "GET", "go_echo").should be_empty
    wrapped.call("main.go", 21, "/login", "POST", "go_echo").should be_empty
    wrapped.call("main.go", 22, "/public", "GET", "go_echo").should be_empty
  end

  it "reads the same wrapper shape on gin and chi" do
    wrapped.call("routers.go", 12, "/gin/me", "GET", "go_gin").should eq(["Protected by Go middleware ginAuth (verified from its body: refuses anonymous callers)"])
    wrapped.call("routers.go", 13, "/gin/open", "GET", "go_gin").should be_empty
    wrapped.call("routers.go", 18, "/chi/me", "GET", "go_chi").should eq(["Protected by Go middleware requireSession (verified from its body: refuses anonymous callers)"])
    wrapped.call("routers.go", 19, "/chi/raw", "GET", "go_chi").should be_empty
  end

  it "does not take a factory's non-handler callback for the handler it wraps" do
    # `loginWith(verify func(string) bool)` refuses a bad password.
    cases.call(30, "/login", "POST").should be_empty
    guards.call("echo_wrap_auth_cases", "gin.go", 13, "/gin/login", "POST", "go_gin").should be_empty
    guards.call("echo_wrap_auth_cases", "gin.go", 14, "/gin/cb", "GET", "go_gin").should be_empty
  end

  it "does not count a refusal made after the handler ran" do
    cases.call(28, "/errmap", "GET").should be_empty  # `if err := fn(c); ... 403`
    cases.call(29, "/errmap2", "GET").should be_empty # `err := next(c)` then 401
    cases.call(41, "/retry", "GET").should be_empty   # 403 after the retry loop
    # An early skip (`if probe { return next(c) }`) leaves the check after it.
    cases.call(42, "/skipped", "GET").should eq(["Protected by Go middleware withSkip (verified from its body: refuses anonymous callers)"])
  end

  it "does not read a CSRF refusal as authentication" do
    cases.call(27, "/csrf", "GET").should be_empty
  end

  it "reads only the handler, leaving Echo's trailing middleware to its call-site options" do
    cases.call(31, "/optstruct", "GET").should be_empty # `AuthOptions{Required: false}`
    cases.call(34, "/skip", "GET").should be_empty      # a `Skipper`
    cases.call(35, "/login3", "POST").should be_empty   # the handler's own 401
    cases.call(43, "/open", "GET").should be_empty
  end

  it "resolves a package by the path the route's file imports it from" do
    cases.call(32, "/dup", "GET").should be_empty # b/mw.Wrap only passes on
    cases.call(33, "/dup2", "GET").should eq(["Protected by Go middleware amw.Wrap (verified from its body: refuses anonymous callers)"])
  end

  it "applies the same rules to net/http wrappers" do
    http = ->(line : Int32, url : String) do
      guards.call("http_wrap_lookalikes", "main.go", line, url, "GET", "go_http")
    end
    http.call(14, "/csrf").should be_empty
    http.call(15, "/login").should be_empty
    http.call(16, "/dup").should be_empty
    http.call(17, "/dup2").should eq(["Protected by Go middleware amw.Wrap (verified from its body: refuses anonymous callers)"])
    http.call(18, "/errmap").should be_empty
    http.call(19, "/errmap2").should be_empty
  end
end
