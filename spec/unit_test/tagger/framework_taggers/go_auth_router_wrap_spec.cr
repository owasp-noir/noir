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

  it "finds the handler whatever form the path takes, and on a gin router in an Echo file" do
    mixed = ->(line : Int32, url : String) do
      guards.call("echo_wrap_auth_mixed", "main.go", line, url, "GET", "go_echo")
    end
    mixed.call(18, "/users").should eq(["Protected by Go middleware withAuth (verified from its body: refuses anonymous callers)"])
    mixed.call(19, "/e/wrapped").should eq(["Protected by Go middleware withAuth (verified from its body: refuses anonymous callers)"])
    # Attributed to Echo by the file, registered on gin: the handler is last.
    mixed.call(24, "/g/trailing").should eq(["Protected by Go middleware ginWrap (verified from its body: refuses anonymous callers)"])
    mixed.call(25, "/g/solo").should eq(["Protected by Go middleware ginWrap (verified from its body: refuses anonymous callers)"])
  end

  it "keeps a group guard that skips public paths through a switch case" do
    guards.call("echo_wrap_auth_mixed", "main.go", 17, "/e/grp/inside", "GET", "go_echo").should eq(["Protected by Go middleware authSwitch (verified from its body: refuses anonymous callers)"])
  end

  it "keeps a guard whose refusal condition also tests a CSRF token" do
    guards.call("echo_wrap_auth_mixed", "main.go", 26, "/g/csrfsess", "GET", "go_gin").should eq(["Protected by Go middleware ginCSRFSess (verified from its body: refuses anonymous callers)"])
  end

  it "reads an early skip in any nested block, and a CSRF arm apart from the session arm after it" do
    order = ->(line : Int32, url : String) do
      guards.call("http_wrap_order", "main.go", line, url, "GET", "go_http")
    end
    guard = ->(name : String) { ["Protected by Go middleware #{name} (verified from its body: refuses anonymous callers)"] }
    order.call(10, "/armfirst").should eq(guard.call("authArmFirst"))
    order.call(11, "/switchpublic").should eq(guard.call("authSwitchPublic"))
    order.call(12, "/multilineif").should eq(guard.call("authMultiLineIf"))
    order.call(13, "/csrfsess").should eq(guard.call("authSessOrCSRF"))
    order.call(14, "/csrfchain").should eq(guard.call("authCSRFChain"))
    order.call(16, "/plain").should eq(guard.call("authPlain"))
    # A 403 a deferred `recover()` writes runs after the handler.
    order.call(15, "/deferrecover").should be_empty
    # The callback is handed the request at the top level, before the 401.
    order.call(17, "/loginreq").should be_empty
  end

  it "resolves an import through its module's path, not the directory names" do
    # Both modules have `internal/mw`; beta-service's `Wrap` only passes on.
    guards.call("http_wrap_modules", "svc2/cmd/main.go", 11, "/beta", "GET", "go_http").should be_empty
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
