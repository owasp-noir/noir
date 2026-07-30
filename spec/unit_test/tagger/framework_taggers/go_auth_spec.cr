require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Write `fixture_lines` to a temp Go file, run GoAuthTagger against a single
# endpoint at `url`/`method` whose route is recorded at `line`, and return
# the (now possibly tagged) endpoint.
def run_go_auth(fixture_lines : Array(String), url : String, method : String, line : Int32) : Endpoint
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("go_rootgroup")
  Dir.mkdir_p(tmpdir)
  file = File.join(tmpdir, "main.go")
  File.write(file, fixture_lines.join("\n"))

  # The group-middleware pre-scan enumerates `.go` files via the file map,
  # so register the fixture there (mirrors the other GoAuthTagger specs).
  locator = CodeLocator.instance
  Dir.glob("#{tmpdir}/**/*").each do |f|
    next if File.directory?(f)
    locator.push("file_map", f)
  end

  noir_options = create_test_options
  noir_options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(file, line))
  details.technology = "go_gin"
  endpoint = Endpoint.new(url, method, [] of Param, details)

  GoAuthTagger.new(noir_options).perform([endpoint])
  FileUtils.rm_rf(tmpdir)
  endpoint
end

describe "GoAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/go/gin_auth"
  main_path = "#{fixture_base}/main.go"

  # main.go line reference:
  # 13: r.GET("/health", func(c *gin.Context) {
  # 17: r.GET("/public", func(c *gin.Context) {
  # 22: api := r.Group("/api")
  # 23: api.Use(AuthMiddleware())
  # 24: api.GET("/profile", func(c *gin.Context) {
  # 29: r.GET("/dashboard", AuthRequired, func(c *gin.Context) {
  # 34: r.DELETE("/admin/users/:id", AdminOnly, func(c *gin.Context) {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects inline auth middleware (AuthRequired)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 29))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("go_auth")
    endpoint.tags[0].description.should contain("AuthRequired")
  end

  it "detects inline AdminOnly middleware" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 34))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/admin/users/1", "DELETE", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AdminOnly")
  end

  it "detects group-level Use(AuthMiddleware)" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 24))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/api/profile", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("AuthMiddleware")
  end

  it "does not tag public endpoints" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    locator = CodeLocator.instance
    Dir.glob("#{fixture_base}/**/*").each do |file|
      next if File.directory?(file)
      locator.push("file_map", file)
    end

    details = Details.new(PathInfo.new(main_path, 13))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/health", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "handles empty code_paths gracefully" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new
    details.technology = "go_gin"
    endpoint = Endpoint.new("/unknown/", "GET", [] of Param, details)

    tagger = GoAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end

# Verify new Go framework targets (Hertz, Iris, GF) are supported by the same tagger
describe "GoAuthTagger (expanded targets)" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/go/gin_auth"
  main_path = "#{fixture_base}/main.go"

  %w[go_hertz go_iris go_gf].each do |tech|
    it "accepts and runs with technology=#{tech}" do
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(fixture_base)

      locator = CodeLocator.instance
      Dir.glob("#{fixture_base}/**/*").each do |file|
        next if File.directory?(file)
        locator.push("file_map", file)
      end

      details = Details.new(PathInfo.new(main_path, 29))
      details.technology = tech
      endpoint = Endpoint.new("/dashboard", "GET", [] of Param, details)

      tagger = GoAuthTagger.new(noir_options)
      tagger.perform([endpoint])

      endpoint.tags.empty?.should be_false
      endpoint.tags[0].tagger.should eq("go_auth")
    end
  end

  it "finds chained .Use() middleware separated from the route by a blank line" do
    tmpdir = File.tempname("go_blank")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "main.go")
    File.write(file, [
      "api := r.Group(\"/api\")",
      "api.Use(AuthMiddleware())",
      "",
      "api.GET(\"/profile\", func(c *gin.Context) {",
      "    c.JSON(200, gin.H{})",
      "})",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(file, 4))
    details.technology = "go_gin"
    endpoint = Endpoint.new("/api/profile", "GET", [] of Param, details)

    GoAuthTagger.new(noir_options).perform([endpoint])
    endpoint.tags.empty?.should be_false
    endpoint.tags[0].description.should contain("AuthMiddleware")

    FileUtils.rm_rf(tmpdir)
  end
end

# A root/empty group (`g.Group("")` / `g.Group("/")`) with a chained
# `.Use(auth)` is recorded with prefix "/", which `prefix_covers?` matches
# against every endpoint. In gin that middleware only guards the group's
# own routes, NOT engine-level static-asset routes — so the broad scope
# must not tag the SPA shell / `/static/*` / favicon (the gotify FP).
describe "GoAuthTagger (root-group static-asset exemption)" do
  # Models the gotify shape: public static routes registered on the engine,
  # then a root/empty group that applies auth middleware to its own routes.
  #  1 package main
  #  2 func main() {
  #  3   g := gin.New()
  #  4   g.GET("/index.html", indexHandler)
  #  5   g.GET("/static/*filepath", staticHandler)
  #  6   g.GET("/favicon.ico", iconHandler)
  #  7   clientAuth := g.Group("")
  #  8   clientAuth.Use(AuthMiddleware())
  #  9   clientAuth.GET("/data", dataHandler)
  # 10 }
  root_group_fixture = [
    "package main",
    "func main() {",
    "  g := gin.New()",
    "  g.GET(\"/index.html\", indexHandler)",
    "  g.GET(\"/static/*filepath\", staticHandler)",
    "  g.GET(\"/favicon.ico\", iconHandler)",
    "  clientAuth := g.Group(\"\")",
    "  clientAuth.Use(AuthMiddleware())",
    "  clientAuth.GET(\"/data\", dataHandler)",
    "}",
  ]

  {"/index.html" => 4, "/static/*filepath" => 5, "/favicon.ico" => 6}.each do |url, line|
    it "does not tag static-asset route #{url} under a root-group .Use" do
      endpoint = run_go_auth(root_group_fixture, url, "GET", line)
      endpoint.tags.any? { |t| t.name == "auth" }.should be_false
    end
  end

  it "still tags a non-static route covered only by the root-group scope" do
    # `/data` lives far from the `.Use` line (no inline match), so it is
    # tagged purely via the group scope — proving the exemption is narrow
    # and does not drop genuinely protected routes.
    endpoint = run_go_auth(root_group_fixture, "/data", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_true
  end

  it "still tags a non-static route under a chained group .Use(auth)" do
    # `g.Group("/admin").Use(auth)` creates the group and registers the
    # middleware in one expression — neither an assignment nor a closure
    # group, so the receiver has to be read off the chain itself.
    chained = [
      "package main",
      "func main() {",
      "  g := gin.New()",
      "  g.Group(\"/admin\").Use(AuthMiddleware())",
      "}",
    ]
    endpoint = run_go_auth(chained, "/admin/users", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_true
  end

  it "still tags a static route under a truly global engine .Use(auth)" do
    # `r.Use(auth)` (no enclosing group) is a real global middleware: every
    # subsequently registered route, static or not, is guarded. The
    # exemption is scoped to root *groups*, so global coverage is unchanged.
    global = [
      "package main",
      "func main() {",
      "  r := gin.New()",
      "  r.Use(AuthMiddleware())",
      "}",
    ]
    endpoint = run_go_auth(global, "/index.html", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_true
  end
end

# Assignment groups (`api := r.Group("/api")`) are not delimited by braces, so
# they cannot share the closure-group stack: modelling both with one stack made
# sibling groups accumulate, resolving the second group's middleware to
# "/api/admin". That both dropped the tag from the routes it really guards and
# — worse for a security tool — claimed auth on unrelated routes that happened
# to sit under the concatenated prefix.
describe "GoAuthTagger (sibling route groups)" do
  #  1 package main
  #  2 func main() {
  #  3   r := gin.Default()
  #  4   api := r.Group("/api")
  #  5   api.Use(AuthMiddleware())
  #  6   admin := r.Group("/admin")
  #  7   admin.Use(AdminAuthMiddleware())
  #  8   reports := r.Group("/reports")
  #  9   register(api, admin, reports)
  # 10 }
  siblings = [
    "package main",
    "func main() {",
    "  r := gin.Default()",
    "  api := r.Group(\"/api\")",
    "  api.Use(AuthMiddleware())",
    "  admin := r.Group(\"/admin\")",
    "  admin.Use(AdminAuthMiddleware())",
    "  reports := r.Group(\"/reports\")",
    "  register(api, admin, reports)",
    "}",
  ]

  it "tags the first group's routes" do
    endpoint = run_go_auth(siblings, "/api/users", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("AuthMiddleware") }.should be_true
  end

  it "tags a later sibling group's routes with its own middleware" do
    endpoint = run_go_auth(siblings, "/admin/stats", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("AdminAuthMiddleware") }.should be_true
  end

  it "does not tag a sibling group that has no middleware" do
    endpoint = run_go_auth(siblings, "/reports/daily", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_false
  end

  it "does not claim auth on a route that merely matches the concatenated prefix" do
    # `/api` has no middleware here and `/internal` does; the endpoint lives
    # under neither guarded group, so tagging it would report an
    # unauthenticated route as authenticated.
    fixture = [
      "package main",
      "func main() {",
      "  r := gin.Default()",
      "  public := r.Group(\"/api\")",
      "  internal := r.Group(\"/internal\")",
      "  internal.Use(SessionAuth())",
      "  registerPublic(public)",
      "}",
    ]
    endpoint = run_go_auth(fixture, "/api/internal/status", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" }.should be_false
  end

  # A group built from a non-literal path (`r.Group(cfg.APIBase + "/v1")`) has a
  # prefix a line-based scanner cannot read. Treating that as the global scope
  # made a single `.Use(auth)` claim protection for every endpoint in the app —
  # on apache/answer, 202 of 412 endpoints, including `/healthz` and the routes
  # registered on the app's explicitly unauthenticated groups. Declining to tag
  # an unresolvable scope is the same call `spring_security` makes for a filter
  # chain scoped only by a matcher it cannot resolve.
  describe "unresolvable group prefixes" do
    computed = [
      "package main",
      "func main() {",
      "  r := gin.Default()",
      "  unAuthV1 := r.Group(cfg.APIBase + \"/api/v1\")",
      "  authV1 := r.Group(cfg.APIBase + \"/api/v1\")",
      "  authV1.Use(authUserMiddleware.MustAuth())",
      "  registerUnAuth(unAuthV1)",
      "  registerAuth(authV1)",
      "}",
    ]

    it "does not tag an unrelated endpoint from a group whose prefix is computed" do
      endpoint = run_go_auth(computed, "/healthz", "GET", 30)
      endpoint.tags.any? { |t| t.name == "auth" }.should be_false
    end

    it "does not tag a sibling public group's routes either" do
      endpoint = run_go_auth(computed, "/api/v1/siteinfo", "GET", 30)
      endpoint.tags.any? { |t| t.name == "auth" }.should be_false
    end

    it "still treats a literal-prefix group as scoped" do
      literal = [
        "package main",
        "func main() {",
        "  r := gin.Default()",
        "  authV1 := r.Group(\"/api/v1\")",
        "  authV1.Use(MustAuth())",
        "  register(authV1)",
        "}",
      ]
      run_go_auth(literal, "/api/v1/me", "GET", 30)
        .tags.any? { |t| t.name == "auth" }.should be_true
      run_go_auth(literal, "/healthz", "GET", 30)
        .tags.any? { |t| t.name == "auth" }.should be_false
    end

    it "still treats a bare engine-level .Use(auth) as global" do
      # Only *group* scopes become unresolvable — a global `.Use` genuinely
      # guards every route registered after it, so this must keep working.
      global = [
        "package main",
        "func main() {",
        "  r := gin.Default()",
        "  r.Use(AuthMiddleware())",
        "}",
      ]
      endpoint = run_go_auth(global, "/anything", "GET", 30)
      endpoint.tags.any? { |t| t.name == "auth" }.should be_true
    end
  end

  it "does not double-count the prefix of a closure group that is also assigned" do
    # `r.Group("/admin", handler)` is a closure group *and* an assignment; the
    # two forms must both resolve to /admin, not /admin/admin.
    both = [
      "package main",
      "func main() {",
      "  r := gin.Default()",
      "  admin := r.Group(\"/admin\", func(c *gin.Context) { c.Next() })",
      "  admin.Use(AdminAuth())",
      "  registerAdmin(admin)",
      "}",
    ]
    endpoint = run_go_auth(both, "/admin/stats", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("AdminAuth") }.should be_true
  end

  it "still inherits the parent group's middleware in a nested group" do
    nested = [
      "package main",
      "func main() {",
      "  r := gin.Default()",
      "  api := r.Group(\"/api\")",
      "  api.Use(AuthMiddleware())",
      "  admin := api.Group(\"/admin\")",
      "  register(api, admin)",
      "}",
    ]
    endpoint = run_go_auth(nested, "/api/admin/stats", "GET", 30)
    endpoint.tags.any? { |t| t.name == "auth" && t.description.includes?("AuthMiddleware") }.should be_true
  end
end
