require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# echo_security/main.go line reference:
#  15: e.Use(middleware.Secure())                 -> global security-headers
#  16: e.Use(middleware.RateLimiter(...))          -> global rate-limit
#  19: e.GET("/health", ...)                       -> public (globals only)
#  24: web := e.Group("/web")
#  25: web.Use(middleware.CSRF())                  -> /web csrf-protection
#  26: web.POST("/transfer", ...)
#  31: upload := e.Group("/upload")
#  32: upload.Use(middleware.BodyLimit("2M"))      -> /upload body-limit
#  33: upload.POST("/file", ...)
#  38: api := e.Group("/api")
#  39: api.Use(middleware.TimeoutWithConfig(...))  -> /api timeout
#  40: api.GET("/report", ...)
#  45: pub := e.Group("/pub")
#  46: pub.Use(middleware.CORSWithConfig(...))     -> /pub cors
#  49: pub.GET("/feed", ...)
#  54: e.POST("/admin/reset", ..., middleware.CSRF()) -> inline csrf-protection
#
# fiber_security/main.go line reference:
#  16: app.Use(helmet.New())                       -> global security-headers
#  17: app.Use(encryptcookie.New(...))             -> global secure-cookies
#  19: app.Get("/status", ...)                     -> globals only
#  24: api := app.Group("/api")
#  25: api.Use(limiter.New())                       -> /api rate-limit
#  26: api.Use(csrf.New())                          -> /api csrf-protection
#  27: api.Post("/orders", ...)
#  33: open.Use(cors.New())                         -> /open cors
#  34: open.Get("/data", ...)

private def tag_named(endpoint : Endpoint, name : String) : Tag?
  endpoint.tags.find { |t| t.name == name }
end

private def seed_file_map(fixture_base : String)
  locator = CodeLocator.instance
  locator.clear_all
  Dir.glob("#{fixture_base}/**/*").each do |file|
    next if File.directory?(file)
    locator.push("file_map", file)
  end
end

private def go_endpoint(path : String, line : Int32, url : String, method : String, tech : String) : Endpoint
  details = Details.new(PathInfo.new(path, line))
  details.technology = tech
  Endpoint.new(url, method, [] of Param, details)
end

describe "GoSecurityTagger" do
  echo_base = "#{__DIR__}/../../../functional_test/fixtures/go/echo_security"
  echo_main = "#{echo_base}/main.go"
  fiber_base = "#{__DIR__}/../../../functional_test/fixtures/go/fiber_security"
  fiber_main = "#{fiber_base}/main.go"

  echo_opts = create_test_options
  echo_opts["base"] = YAML::Any.new(echo_base)

  it "targets the Go web framework techs" do
    techs = GoSecurityTagger.target_techs
    techs.should contain("go_echo")
    techs.should contain("go_gin")
    techs.should contain("go_fiber")
    techs.should contain("go_chi")
  end

  describe "Echo: global middleware (.Use at the root)" do
    it "applies security-headers + rate-limit to a public route" do
      seed_file_map(echo_base)
      endpoint = go_endpoint(echo_main, 19, "/health", "GET", "go_echo")
      GoSecurityTagger.new(echo_opts).perform([endpoint])

      tag_named(endpoint, "security-headers").should_not be_nil
      tag_named(endpoint, "rate-limit").should_not be_nil
      # The group scopes must not bleed onto /health.
      tag_named(endpoint, "csrf-protection").should be_nil
      tag_named(endpoint, "body-limit").should be_nil
      tag_named(endpoint, "timeout").should be_nil
      tag_named(endpoint, "cors").should be_nil
    end
  end

  describe "Echo: group-scoped middleware" do
    it "tags csrf-protection on the /web group, plus inherited globals" do
      seed_file_map(echo_base)
      endpoint = go_endpoint(echo_main, 26, "/web/transfer", "POST", "go_echo")
      GoSecurityTagger.new(echo_opts).perform([endpoint])

      csrf = tag_named(endpoint, "csrf-protection")
      csrf.should_not be_nil
      csrf.not_nil!.tagger.should eq("go_security")
      csrf.not_nil!.description.should contain("CSRF")
      tag_named(endpoint, "security-headers").should_not be_nil
      tag_named(endpoint, "rate-limit").should_not be_nil
      tag_named(endpoint, "body-limit").should be_nil
    end

    it "tags body-limit on the /upload group" do
      seed_file_map(echo_base)
      endpoint = go_endpoint(echo_main, 33, "/upload/file", "POST", "go_echo")
      GoSecurityTagger.new(echo_opts).perform([endpoint])

      tag_named(endpoint, "body-limit").should_not be_nil
      tag_named(endpoint, "csrf-protection").should be_nil
    end

    it "tags timeout on the /api group" do
      seed_file_map(echo_base)
      endpoint = go_endpoint(echo_main, 40, "/api/report", "GET", "go_echo")
      GoSecurityTagger.new(echo_opts).perform([endpoint])

      tag_named(endpoint, "timeout").should_not be_nil
      tag_named(endpoint, "csrf-protection").should be_nil
    end

    it "tags cors on the /pub group" do
      seed_file_map(echo_base)
      endpoint = go_endpoint(echo_main, 49, "/pub/feed", "GET", "go_echo")
      GoSecurityTagger.new(echo_opts).perform([endpoint])

      tag_named(endpoint, "cors").should_not be_nil
      tag_named(endpoint, "timeout").should be_nil
    end
  end

  describe "Echo: inline route-level middleware" do
    it "tags csrf-protection from a trailing middleware arg on the route call" do
      seed_file_map(echo_base)
      endpoint = go_endpoint(echo_main, 54, "/admin/reset", "POST", "go_echo")
      GoSecurityTagger.new(echo_opts).perform([endpoint])

      csrf = tag_named(endpoint, "csrf-protection")
      csrf.should_not be_nil
      csrf.not_nil!.description.should contain("inline")
      tag_named(endpoint, "security-headers").should_not be_nil
      tag_named(endpoint, "rate-limit").should_not be_nil
      tag_named(endpoint, "body-limit").should be_nil
    end
  end

  describe "Fiber framework family" do
    fiber_opts = create_test_options
    fiber_opts["base"] = YAML::Any.new(fiber_base)

    it "tags global helmet (security-headers) + encryptcookie (secure-cookies)" do
      seed_file_map(fiber_base)
      endpoint = go_endpoint(fiber_main, 19, "/status", "GET", "go_fiber")
      GoSecurityTagger.new(fiber_opts).perform([endpoint])

      tag_named(endpoint, "security-headers").should_not be_nil
      tag_named(endpoint, "secure-cookies").should_not be_nil
      tag_named(endpoint, "rate-limit").should be_nil
    end

    it "tags rate-limit (limiter) + csrf (csrf.New) on the /api group" do
      seed_file_map(fiber_base)
      endpoint = go_endpoint(fiber_main, 27, "/api/orders", "POST", "go_fiber")
      GoSecurityTagger.new(fiber_opts).perform([endpoint])

      tag_named(endpoint, "rate-limit").should_not be_nil
      tag_named(endpoint, "csrf-protection").should_not be_nil
      tag_named(endpoint, "security-headers").should_not be_nil
      tag_named(endpoint, "secure-cookies").should_not be_nil
    end

    it "tags cors (cors.New) on the /open group only" do
      seed_file_map(fiber_base)
      endpoint = go_endpoint(fiber_main, 34, "/open/data", "GET", "go_fiber")
      GoSecurityTagger.new(fiber_opts).perform([endpoint])

      tag_named(endpoint, "cors").should_not be_nil
      tag_named(endpoint, "csrf-protection").should be_nil
    end
  end

  it "handles empty code_paths gracefully" do
    seed_file_map(echo_base)
    details = Details.new
    details.technology = "go_echo"
    endpoint = Endpoint.new("/nowhere", "GET", [] of Param, details)

    GoSecurityTagger.new(echo_opts).perform([endpoint])
    # Globals from the pre-scan still match by URL prefix even without a
    # code_path, but the run must not raise.
    endpoint.tags.empty?.should be_false
  end

  it "does not over-match a sibling prefix (/web vs /website)" do
    seed_file_map(echo_base)
    endpoint = go_endpoint(echo_main, 19, "/website", "GET", "go_echo")
    GoSecurityTagger.new(echo_opts).perform([endpoint])
    tag_named(endpoint, "csrf-protection").should be_nil
  end

  it "scopes a closure-style group's middleware to its prefix only" do
    tmpdir = File.tempname("go_sec_closure")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "main.go")
    File.write(file, [
      "func main() {",
      "    r := chi.NewRouter()",
      "    r.Get(\"/open\", openHandler)",
      "    r.Route(\"/admin\", func(r chi.Router) {",
      "        r.Use(csrf.Protect(key))",
      "        r.Get(\"/panel\", panelHandler)",
      "    })",
      "}",
    ].join("\n"))

    opts = create_test_options
    opts["base"] = YAML::Any.new(tmpdir)
    seed_file_map(tmpdir)

    # /admin/panel is inside the closure -> csrf-protection.
    admin = go_endpoint(file, 6, "/admin/panel", "GET", "go_chi")
    GoSecurityTagger.new(opts).perform([admin])
    tag_named(admin, "csrf-protection").should_not be_nil

    # /open is outside the closure -> no csrf-protection leak.
    open = go_endpoint(file, 3, "/open", "GET", "go_chi")
    GoSecurityTagger.new(opts).perform([open])
    tag_named(open, "csrf-protection").should be_nil

    FileUtils.rm_rf(tmpdir)
  end

  it "exempts static-asset routes from a global root cors scope" do
    # Models gotify: a global `r.Use(cors.New(...))` plus static routes
    # served off the engine (the SPA shell / `/static/*`). CORS is global,
    # so API routes are tagged, but the static assets — registered outside
    # the middleware chain — must not be.
    #  1 package main
    #  2 func main() {
    #  3   r := gin.New()
    #  4   r.GET("/index.html", indexHandler)
    #  5   r.GET("/static/*filepath", staticHandler)
    #  6   r.Use(cors.New(corsConfig))
    #  7   r.GET("/api/data", dataHandler)
    #  8 }
    tmpdir = File.tempname("go_sec_static")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "main.go")
    File.write(file, [
      "package main",
      "func main() {",
      "    r := gin.New()",
      "    r.GET(\"/index.html\", indexHandler)",
      "    r.GET(\"/static/*filepath\", staticHandler)",
      "    r.Use(cors.New(corsConfig))",
      "    r.GET(\"/api/data\", dataHandler)",
      "}",
    ].join("\n"))

    opts = create_test_options
    opts["base"] = YAML::Any.new(tmpdir)
    seed_file_map(tmpdir)

    index = go_endpoint(file, 4, "/index.html", "GET", "go_gin")
    static = go_endpoint(file, 5, "/static/*filepath", "GET", "go_gin")
    api = go_endpoint(file, 7, "/api/data", "GET", "go_gin")
    GoSecurityTagger.new(opts).perform([index, static, api])

    tag_named(index, "cors").should be_nil
    tag_named(static, "cors").should be_nil
    tag_named(api, "cors").should_not be_nil

    FileUtils.rm_rf(tmpdir)
  end
end
