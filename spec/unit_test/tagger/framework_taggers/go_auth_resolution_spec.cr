require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

private def guard_resolution_endpoint(fixture : String, file : String, line : Int32, url : String,
                                      tech : String = "go_gin", method : String = "GET") : Endpoint
  base = File.expand_path("../../../functional_test/fixtures/go/#{fixture}", __DIR__)
  CodeLocator.instance.clear_all
  Dir.glob("#{base}/**/*").each { |path| CodeLocator.instance.register_path(path) unless File.directory?(path) }
  options = create_test_options
  options["base"] = YAML::Any.new(base)
  details = Details.new(PathInfo.new("#{base}/#{file}", line))
  details.technology = tech
  endpoint = Endpoint.new(url, method, [] of Param, details)
  endpoints = [endpoint]
  NoirTaggers.run_tagger(endpoints, options, "go_auth")
  endpoints.first
end

describe "GoAuthTagger guard resolution (#3567)" do
  {
    "a nearby Use with a known body"  => {"gin_auth", "main.go", 24, "/api/profile", "go_gin", "GET"},
    "a constructor with a known body" => {"gin_auth", "main.go", 47, "/v1/users/add", "go_gin", "POST"},
    "a closure's trailing middleware" => {"chi_auth", "main.go", 24, "/user", "go_chi", "GET"},
    "a closure's Use"                 => {"chi_auth", "main.go", 49, "/me", "go_chi", "GET"},
    "a file-wide middleware binding"  => {"chi_auth", "main.go", 34, "/repos/{id}/star", "go_chi", "POST"},
    "a wrapped mux"                   => {"http_wrapped", "api/api.go", 12, "/v1/items", "go_http", "POST"},
    "a local wrapping closure"        => {"http_wrapped", "reader/reader.go", 16, "/reader/edit", "go_http", "POST"},
    "a setting that can lift auth"    => {"http_wrapped", "jobs/jobs.go", 11, "/jobs/run", "go_http", "POST"},
    "an RPC procedure scope"          => {"connect_rpc_public_procedures", "server/api/server.go", 27, "/notes.api.AuthService/GetCurrentUser", "go_connect_rpc", "POST"},
  }.each do |path, args|
    it "marks #{path} as matched" do
      endpoint = guard_resolution_endpoint(*args)
      endpoint.tags.any?(&.name.in?("auth", "authz")).should be_true
      endpoint.resolution.try(&.["guard"]?).should eq(Endpoint::RESOLUTION_HEURISTIC)
    end
  end

  {
    "an inline body"       => {"gin_auth", "main.go", 52, "/home", "go_gin", "GET"},
    "a With body"          => {"chi_auth", "main.go", 51, "/feed", "go_chi", "GET"},
    "a handler wrapper"    => {"echo_wrap_auth", "main.go", 14, "/admin/users", "go_echo", "GET"},
    "an imported function" => {"http_wrap_lookalikes", "main.go", 17, "/dup2", "go_http", "GET"},
    "a replaced import"    => {"http_wrap_replace", "app/main.go", 11, "/forked", "go_http", "GET"},
  }.each do |path, args|
    it "leaves #{path} followed" do
      endpoint = guard_resolution_endpoint(*args)
      endpoint.tags.any?(&.name.in?("auth", "authz")).should be_true
      endpoint.resolution.should be_nil
      JSON.parse(endpoint.to_json).as_h.has_key?("resolution").should be_false
    end
  end

  it "marks a name-only inline match and a JWT pattern without resolving a library import" do
    [
      ["package main", "func routes(r *gin.Engine) {", %(r.GET("/named", AuthRequired, h)), "}"],
      ["package main", "func routes(r *gin.Engine) {", "r.Use(jwtauth.Verifier(token))", %(r.GET("/named", h)), "}"],
    ].each do |lines|
      endpoint = run_go_auth(lines, "/named", "GET", lines.index!(&.includes?("r.GET")) + 1)
      endpoint.tags.map(&.name).should eq(["auth"])
      endpoint.resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "leaves an endpoint with no guard unmarked" do
    guard_resolution_endpoint("gin_auth", "main.go", 13, "/health").resolution.should be_nil
  end

  it "writes back all three claims through the tagger runner" do
    base = File.expand_path("../../../functional_test/fixtures/go/gin_auth", __DIR__)
    # Populate the file map first, as a scan does.
    guard_resolution_endpoint("gin_auth", "main.go", 24, "/api/profile")
    options = create_test_options
    options["base"] = YAML::Any.new(base)
    details = Details.new(PathInfo.new("#{base}/main.go", 24))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/api/profile", "GET", details)
    endpoint.resolution = {"prefix" => Endpoint::RESOLUTION_UNRESOLVED, "handler" => Endpoint::RESOLUTION_HEURISTIC}
    endpoints = [endpoint]
    NoirTaggers.run_tagger(endpoints, options, "go_auth")
    endpoints.first.resolution.should eq({"prefix" => "unresolved", "handler" => "heuristic", "guard" => "heuristic"})
    endpoint.resolution.should eq({"prefix" => "unresolved", "handler" => "heuristic"})
  end
end

# Keep names deliberately different from the inline name patterns.
describe "GoAuthTagger direct guard evidence" do
  it "keeps one followed guard despite matched evidence, and reads handler clauses" do
    dir = File.tempname("go_guard_resolution")
    Dir.mkdir_p(dir)
    file = File.join(dir, "main.go")
    source = <<-GO
      package main
      func checkpoint(c *gin.Context) {
          if c.GetHeader("Authorization") == "" {
              c.AbortWithStatus(401)
          }
      }
      func permit(c *gin.Context) {
          if !c.IsAdmin {
              c.AbortWithStatus(403)
          }
      }
      func refuses(c *gin.Context) bool {
          if c.GetHeader("Authorization") == "" {
              c.AbortWithStatus(401)
          }
          return true
      }
      func checked(c *gin.Context) {
          if refuses(c) {
              return
          }
      }
      func header(c *gin.Context) {
          token := c.GetHeader("Authorization")
          if token == "" {
              return echo.ErrUnauthorized
          }
      }
      func routes(r *gin.Engine) {
          r.GET("/mixed", AuthRequired, checkpoint, h)
          r.GET("/permission", permit, h)
          r.GET("/checked", checked)
          r.GET("/header", header)
          r.GET("/guessed-handler", checked)
      }
      GO
    File.write(file, source)
    CodeLocator.instance.clear_all
    CodeLocator.instance.register_path(file)
    options = create_test_options
    options["base"] = YAML::Any.new(dir)
    endpoints = %w[mixed permission checked header guessed-handler].map do |name|
      row = source.lines.index!(&.includes?(%("/#{name}"))) + 1
      details = Details.new(PathInfo.new(file, row))
      details.technology = "go_gin"
      endpoint = Endpoint.new("/#{name}", "GET", details)
      if name.in?("checked", "header", "guessed-handler")
        handler = name == "guessed-handler" ? "checked" : name
        endpoint.handler = Handler.new(handler, file, source.lines.index!(&.starts_with?("func #{handler}(")) + 1)
      end
      endpoint.resolution = {"handler" => Endpoint::RESOLUTION_HEURISTIC} if name == "guessed-handler"
      endpoint
    end
    NoirTaggers.run_tagger(endpoints, options, "go_auth")
    endpoints.first.tags.map(&.description).should eq(["Protected by Go AuthRequired middleware"])
    endpoints[1].tags.map(&.name).should eq(["authz"])
    endpoints.first(4).each(&.resolution.should(be_nil))
    endpoints.last.resolution.should eq({"handler" => "heuristic", "guard" => "heuristic"})
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end

describe "GoAuthTagger matched definition paths" do
  it "does not certify a package function hidden by a declaration" do
    [
      {"func routes(r *gin.Engine) {", "checkpoint := func(c *gin.Context) { c.Next() }"},
      {"func routes(r *gin.Engine, checkpoint gin.HandlerFunc) {", ""},
      {"func routes(r *gin.Engine) {", "var checkpoint gin.HandlerFunc"},
      {"func routes(r *gin.Engine) {", "checkpoint, err := makeGuard()"},
    ].each do |head, declaration|
      source = [
        "package main",
        "func checkpoint(c *gin.Context) {",
        %(  if c.GetHeader("Authorization") == "" {), "  c.AbortWithStatus(401)", "  }",
        "}",
        head, declaration, %(r.GET("/x", checkpoint, h)), "}",
      ]
      endpoint = run_go_auth(source, "/x", "GET", 9)
      endpoint.tags.map(&.name).should eq(["auth"])
      endpoint.resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "does not tag an Echo handler that refuses without a caller check" do
    lines = [
      "package main", "func login(c echo.Context) error {", "  return echo.ErrUnauthorized", "}",
      "func routes(e *echo.Echo) {", %(e.POST("/login", login, logging)), "}",
    ]
    endpoint = run_go_auth(lines, "/login", "POST", 6, "go_echo")
    endpoint.tags.should be_empty
    endpoint.resolution.should be_nil
  end

  it "keeps an unread factory flag heuristic" do
    lines = [
      "package main", "func checkpoint(required bool) gin.HandlerFunc {", "  return func(c *gin.Context) {",
      "    if required {", %(      if c.GetHeader("Authorization") == "" {), "        c.AbortWithStatus(401)", "      }", "    }", "  }", "}",
      "func routes(r *gin.Engine) {", %(r.GET("/x", checkpoint(cfg.Required), h)), "}",
    ]
    endpoint = run_go_auth(lines, "/x", "GET", 12)
    endpoint.tags.map(&.name).should eq(["auth"])
    endpoint.resolution.should eq({"guard" => "heuristic"})
    lines[11] = %(r.GET("/x", checkpoint(true), h))
    run_go_auth(lines, "/x", "GET", 12).resolution.should be_nil
  end

  it "does not certify a refusal found in a package selected by basename" do
    dir = File.tempname("go_guard_import")
    files = {
      "go.mod"  => "module example.com/app\n",
      "main.go" => <<-GO,
        package main
        import "example.com/app/b/response"
        func gate(next http.Handler) http.Handler {
            return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
                if r.Header.Get("Authorization") == "" {
                    response.Reject(w, r)
                    return
                }
                next.ServeHTTP(w, r)
            })
        }
        func routes() {
            mux := http.NewServeMux()
            mux.Handle("/x", gate(h))
        }
        GO
      "a/response/response.go" => "package response\nfunc Reject(w http.ResponseWriter, r *http.Request) {\n w.WriteHeader(401)\n}\n",
      "b/response/response.go" => "package response\nfunc Reject(w http.ResponseWriter, r *http.Request) {\n fmt.Println(r)\n}\n",
    }
    CodeLocator.instance.clear_all
    files.each do |relative, source|
      path = File.join(dir, relative)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, source)
      CodeLocator.instance.register_path(path)
    end
    options = create_test_options
    options["base"] = YAML::Any.new(dir)
    details = Details.new(PathInfo.new(File.join(dir, "main.go"), 14))
    details.technology = "go_http"
    endpoints = [Endpoint.new("/x", "GET", details)]
    NoirTaggers.run_tagger(endpoints, options, "go_auth")
    endpoints.first.tags.map(&.name).should eq(["auth"])
    endpoints.first.resolution.should eq({"guard" => "heuristic"})
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
