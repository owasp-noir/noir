require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Write `files` (relative path -> source) to a temp tree, run GoAuthTagger on
# one endpoint per route ({method, url, file, text on the route's line}) and
# return them keyed "METHOD url".
private def router_scope_scan(files : Hash(String, String), routes : Array({String, String, String, String}), tech : String) : Hash(String, Endpoint)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("go_router_scope")
  files.each do |rel, body|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  endpoints = routes.map do |(method, url, rel, needle)|
    line = files[rel].lines.index!(&.includes?(needle)) + 1
    details = Details.new(PathInfo.new(File.join(tmpdir, rel), line))
    details.technology = tech
    Endpoint.new(url, method, [] of Param, details)
  end
  tagged = GoAuthTagger.new(options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  tagged.to_h { |endpoint| {"#{endpoint.method} #{endpoint.url}", endpoint} }
end

private def guarded?(endpoint : Endpoint) : Bool
  endpoint.tags.any? { |tag| tag.name == "auth" || tag.name == "authz" }
end

GIN_AUTH = <<-GO
  package main

  import (
  \t"net/http"

  \t"github.com/gin-gonic/gin"
  )

  func Auth() gin.HandlerFunc {
  \treturn func(c *gin.Context) {
  \t\tif c.GetHeader("Authorization") == "" {
  \t\t\tc.AbortWithStatus(http.StatusUnauthorized)
  \t\t}
  \t}
  }

  GO

GIN_MOD = "module example.com/app\n\nrequire github.com/gin-gonic/gin v1.9.0\n"

# A `.Use` reaches the routes of the router it is registered on, after it:
# not another router, another program, a sibling group or an earlier route.
describe "GoAuthTagger (router identity of .Use guards)" do
  it "keeps a mounted subrouter's .Use off the root router's routes (chi)" do
    src = <<-GO
      package main

      import (
      \t"net/http"

      \t"github.com/go-chi/chi/v5"
      )

      func AdminOnly(next http.Handler) http.Handler {
      \treturn http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
      \t\tif ok, _ := r.Context().Value("admin").(bool); !ok {
      \t\t\thttp.Error(w, "forbidden", http.StatusForbidden)
      \t\t\treturn
      \t\t}
      \t\tnext.ServeHTTP(w, r)
      \t})
      }

      func adminRouter() chi.Router {
      \tr := chi.NewRouter()
      \tr.Use(AdminOnly)
      \tr.Get("/accounts", func(w http.ResponseWriter, r *http.Request) {})
      \treturn r
      }

      func main() {
      \tr := chi.NewRouter()
      \tr.Get("/ping", func(w http.ResponseWriter, r *http.Request) {})
      \tr.Mount("/admin", adminRouter())
      }
      GO
    result = router_scope_scan({"go.mod" => "module x\n", "main.go" => src},
      [{"GET", "/admin/accounts", "main.go", %("/accounts")}, {"GET", "/ping", "main.go", %("/ping")}], "go_chi")
    guarded?(result["GET /admin/accounts"]).should be_true
    guarded?(result["GET /ping"]).should be_false
  end

  it "keeps one module's .Use off another module's routes (fiber)" do
    secured = <<-GO
      package main

      import (
      \t"github.com/gofiber/fiber/v2"
      \t"github.com/gofiber/fiber/v2/middleware/keyauth"
      )

      func main() {
      \tapp := fiber.New()
      \tapp.Use(keyauth.New(keyauth.Config{KeyLookup: "header:x"}))
      \tapp.Get("/private", func(c *fiber.Ctx) error { return nil })
      }
      GO
    public = <<-GO
      package main

      import "github.com/gofiber/fiber/v2"

      func Register(app *fiber.App) {
      \tapp.Post("/signup", func(c *fiber.Ctx) error { return nil })
      }
      GO
    result = router_scope_scan({"secured/go.mod" => "module s\n", "secured/main.go" => secured,
                                "public/go.mod" => "module p\n", "public/routes.go" => public},
      [{"GET", "/private", "secured/main.go", %("/private")}, {"POST", "/signup", "public/routes.go", %("/signup")}], "go_fiber")
    guarded?(result["GET /private"]).should be_true
    guarded?(result["POST /signup"]).should be_false
  end

  it "does not guard a route registered before the .Use (gin)" do
    src = GIN_AUTH + <<-GO
      func main() {
      \tr := gin.Default()
      \tr.GET("/pub", func(c *gin.Context) {})
      \tr.Use(Auth())
      \tr.GET("/priv", func(c *gin.Context) {})
      }
      GO
    result = router_scope_scan({"go.mod" => GIN_MOD, "main.go" => src},
      [{"GET", "/pub", "main.go", %("/pub")}, {"GET", "/priv", "main.go", %("/priv")}], "go_gin")
    guarded?(result["GET /pub"]).should be_false
    guarded?(result["GET /priv"]).should be_true
  end

  it "does not guard a sibling group under the same prefix, with or without blank lines (gin)" do
    [true, false].each do |spaced|
      gap = spaced ? "\n" : ""
      src = GIN_AUTH + <<-GO
        func main() {
        \tr := gin.Default()
        \tv1 := r.Group("/api")
        \tv1.Use(Auth())
        \tv1.GET("/user", func(c *gin.Context) {})
        #{gap}\tping := r.Group("/api/ping")
        \tping.GET("/", func(c *gin.Context) {})
        #{gap}\thealth := r.Group("/health")
        \thealth.GET("/", func(c *gin.Context) {})
        }
        GO
      result = router_scope_scan({"go.mod" => GIN_MOD, "main.go" => src},
        [{"GET", "/api/user", "main.go", "v1.GET"}, {"GET", "/api/ping/", "main.go", "ping.GET"},
         {"GET", "/health/", "main.go", "health.GET"}], "go_gin")
      guarded?(result["GET /api/user"]).should be_true
      guarded?(result["GET /api/ping/"]).should be_false
      guarded?(result["GET /health/"]).should be_false
    end
  end

  it "still guards routes a helper in another file registers on the router" do
    main = GIN_AUTH + <<-GO
      func main() {
      \tr := gin.Default()
      \tr.Use(Auth())
      \troutes.Setup(r)
      }
      GO
    routes = <<-GO
      package routes

      import "github.com/gin-gonic/gin"

      func Setup(r *gin.Engine) {
      \tapi := r.Group("/api")
      \tapi.GET("/items", func(c *gin.Context) {})
      }
      GO
    result = router_scope_scan({"go.mod" => GIN_MOD, "main.go" => main, "routes/routes.go" => routes},
      [{"GET", "/api/items", "routes/routes.go", "api.GET"}], "go_gin")
    guarded?(result["GET /api/items"]).should be_true
  end

  # vikunja: `registerAPIRoutes(a)` and `registerAPIRoutesV2(e, a2)`, both
  # helpers naming their group parameter `a`.
  echo_helpers = <<-GO
    package routes

    import (
    \t"net/http"

    \t"github.com/labstack/echo/v4"
    )

    func auth() echo.MiddlewareFunc {
    \treturn func(next echo.HandlerFunc) echo.HandlerFunc {
    \t\treturn func(c echo.Context) error {
    \t\t\tif c.Request().Header.Get("Authorization") == "" {
    \t\t\t\treturn c.JSON(http.StatusUnauthorized, nil)
    \t\t\t}
    \t\t\treturn next(c)
    \t\t}
    \t}
    }

    func RegisterRoutes(e *echo.Echo) {
    \ta := e.Group("/api/v1")
    \tregisterV1(a)
    \ta2 := e.Group("/api/v2")
    \tregisterV2(e, a2)
    }

    func registerV2(e *echo.Echo, a *echo.Group) {
    \ta.Use(auth())
    \ta.GET("/v2-only", h)
    }

    func registerV1(a *echo.Group) {
    \tn := a.Group("")
    \tn.POST("/login", h)
    \ta.Use(auth())
    \ta.GET("/me", h)
    }
    GO

  it "keeps a .Use on one helper's group parameter off a sibling helper's routes (echo)" do
    result = router_scope_scan({"go.mod" => "module e\n", "routes.go" => echo_helpers},
      [{"POST", "/api/v1/login", "routes.go", %("/login")}, {"GET", "/api/v1/me", "routes.go", %("/me")},
       {"GET", "/api/v2/v2-only", "routes.go", %("/v2-only")}], "go_echo")
    guarded?(result["POST /api/v1/login"]).should be_false
    guarded?(result["GET /api/v1/me"]).should be_true
    guarded?(result["GET /api/v2/v2-only"]).should be_true
  end

  it "still guards a sibling helper handed the same group, or called from elsewhere" do
    # Handed the same group first, so `n` is created after its `.Use`.
    same = echo_helpers.sub("\tregisterV1(a)\n", "").sub("registerV2(e, a2)", "registerV2(e, a)\n\tregisterV1(a)")
    result = router_scope_scan({"go.mod" => "module e\n", "routes.go" => same},
      [{"POST", "/api/v1/login", "routes.go", %("/login")}], "go_echo")
    guarded?(result["POST /api/v1/login"]).should be_true

    elsewhere = echo_helpers + "\nfunc Other(g *echo.Group) {\n\tregisterV1(g)\n}\n"
    result = router_scope_scan({"go.mod" => "module e\n", "routes.go" => elsewhere},
      [{"POST", "/api/v1/login", "routes.go", %("/login")}], "go_echo")
    guarded?(result["POST /api/v1/login"]).should be_true
  end

  # `secure(a)` guards group `a`; `pub` is handed a group that is, or may
  # be, that one.
  # Fiber runs a group's middleware for every route under its path: the
  # `/api` group's auth also covers the separately built `/api/public`.
  it "does not separate sibling groups by identity on fiber" do
    src = <<-GO
      package main

      import "github.com/gofiber/fiber/v2"

      func auth(c *fiber.Ctx) error {
      \tif c.Get("Authorization") == "" {
      \t\treturn c.SendStatus(fiber.StatusUnauthorized)
      \t}
      \treturn c.Next()
      }

      func main() {
      \tapp := fiber.New()
      \ta := app.Group("/api")
      \tsecure(a)
      \tb := app.Group("/api/public")
      \tpub(b)
      }

      func secure(a fiber.Router) {
      \ta.Use(auth)
      \ta.Get("/me", h)
      }

      func pub(a fiber.Router) {
      \ta.Get("/items", h)
      }
      GO
    result = router_scope_scan({"go.mod" => "module f\n", "main.go" => src},
      [{"GET", "/api/public/items", "main.go", %("/items")}], "go_fiber")
    guarded?(result["GET /api/public/items"]).should be_true
  end

  it "keeps a sibling helper guarded unless its group is provably another one" do
    helpers = echo_helpers.split("func RegisterRoutes").first + <<-GO
      func secure(a *echo.Group) {
      \ta.Use(auth())
      \ta.GET("/me", h)
      }

      func pub(a *echo.Group) {
      \ta.GET("/items", h)
      }
      GO
    scan = ->(caller : String, extra : Hash(String, String)) do
      files = {"go.mod" => "module e\n", "routes.go" => helpers + caller}.merge(extra)
      guarded?(router_scope_scan(files, [{"GET", "/items", "routes.go", %("/items")}], "go_echo")["GET /items"])
    end
    # An alias, and a group derived from the guarded one after its `.Use`.
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\tb := a\n\tpub(b)\n}\n", {} of String => String).should be_true
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\tv := a.Group(\"/v\")\n\tpub(v)\n}\n", {} of String => String).should be_true
    # An argument that is not a plain identifier.
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\to := e.Group(\"/o\")\n\tpub(o)\n\tpub(a.Group(\"/w\"))\n}\n", {} of String => String).should be_true
    # Both the caller's own parameters.
    scan.call("func setup(authed, public *echo.Group) {\n\tsecure(authed)\n\tpub(public)\n}\n", {} of String => String).should be_true
    # A second caller in another file of the package.
    other = "package routes\n\nfunc Admin(e *echo.Echo) {\n\tg := e.Group(\"/admin\")\n\tsecure(g)\n\tpub(g)\n}\n"
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\tp := e.Group(\"/open\")\n\tpub(p)\n}\n", {"admin.go" => other}).should be_true
    # A second caller on one line, and the helper handed on as a value.
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\tp := e.Group(\"/open\")\n\tpub(p)\n\textra(a)\n}\n\nfunc extra(g *echo.Group) { pub(g) }\n", {} of String => String).should be_true
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\tp := e.Group(\"/open\")\n\tpub(p)\n\tapply(a, pub)\n}\n", {} of String => String).should be_true
    # Two groups the one caller built side by side: provably different.
    scan.call("func R(e *echo.Echo) {\n\ta := e.Group(\"/api\")\n\tsecure(a)\n\tp := e.Group(\"/open\")\n\tpub(p)\n}\n", {} of String => String).should be_false
  end

  it "reads a handler that refuses a missing or wrong credential header" do
    src = <<-GO
      package main

      import "github.com/labstack/echo/v4"

      func main() {
      \te := echo.New()
      \te.PATCH("/test/:table", HandleTesting)
      \te.POST("/present", Present)
      \te.POST("/matches", Matches)
      \te.POST("/rebound", Rebound)
      \te.POST("/later", Later)
      }

      func HandleTesting(c echo.Context) error {
      \ttoken := c.Request().Header.Get("Authorization")
      \tif token != config.TestingToken() {
      \t\treturn echo.ErrForbidden
      \t}
      \treturn nil
      }

      func Present(c echo.Context) error {
      \ttoken := c.Request().Header.Get("Authorization")
      \tif token != "" {
      \t\treturn echo.ErrForbidden
      \t}
      \treturn nil
      }

      func Rebound(c echo.Context) error {
      \ttoken := c.Request().Header.Get("Authorization")
      \ttoken = strings.TrimPrefix(token, "Bearer ")
      \tif token != config.TestingToken() {
      \t\treturn echo.ErrForbidden
      \t}
      \treturn nil
      }

      func Later(c echo.Context) error {
      \ttruncateTables()
      \ttoken := c.Request().Header.Get("Authorization")
      \tif token != config.TestingToken() {
      \t\treturn echo.ErrForbidden
      \t}
      \treturn nil
      }

      func Matches(c echo.Context) error {
      \ttoken := c.QueryParam("token")
      \tif token == secret {
      \t\treturn echo.ErrForbidden
      \t}
      \treturn nil
      }
      GO
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("go_handler_credential")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "main.go")
    File.write(file, src)
    CodeLocator.instance.register_path(file)
    options = create_test_options
    options["base"] = YAML::Any.new(tmpdir)
    lines = src.lines
    endpoints = {"PATCH" => {"/test/:table", "HandleTesting"}, "POST" => {"/present", "Present"}}.map do |method, (url, fn)|
      details = Details.new(PathInfo.new(file, lines.index!(&.includes?(%("#{url}"))) + 1))
      details.technology = "go_echo"
      endpoint = Endpoint.new(url, method, [] of Param, details)
      endpoint.handler = Handler.new(fn, file, lines.index!(&.starts_with?("func #{fn}(")) + 1)
      endpoint
    end
    matches = Details.new(PathInfo.new(file, lines.index!(&.includes?(%("/matches"))) + 1))
    matches.technology = "go_echo"
    endpoint = Endpoint.new("/matches", "POST", [] of Param, matches)
    endpoint.handler = Handler.new("Matches", file, lines.index!(&.starts_with?("func Matches(")) + 1)
    endpoints << endpoint
    rebound = Details.new(PathInfo.new(file, lines.index!(&.includes?(%("/rebound"))) + 1))
    rebound.technology = "go_echo"
    endpoint = Endpoint.new("/rebound", "POST", [] of Param, rebound)
    endpoint.handler = Handler.new("Rebound", file, lines.index!(&.starts_with?("func Rebound(")) + 1)
    endpoints << endpoint
    later = Details.new(PathInfo.new(file, lines.index!(&.includes?(%("/later"))) + 1))
    later.technology = "go_echo"
    endpoint = Endpoint.new("/later", "POST", [] of Param, later)
    endpoint.handler = Handler.new("Later", file, lines.index!(&.starts_with?("func Later(")) + 1)
    endpoints << endpoint
    tagged = GoAuthTagger.new(options).perform(endpoints)
    FileUtils.rm_rf(tmpdir)
    guarded?(tagged[0]).should be_true
    tagged[0].tags[0].description.should contain("Authorization")
    # The expected value is a setting: empty, it admits a request without the header.
    tagged[0].tags[0].description.should contain("expected value comes from config.TestingToken()")
    # Refusing the callers that send a credential, or the one that matches, is
    # not authentication.
    guarded?(tagged[1]).should be_false
    guarded?(tagged[2]).should be_false
    # The local no longer holds the header when it is checked.
    guarded?(tagged[3]).should be_false
    # The handler did its work before it checked.
    guarded?(tagged[4]).should be_false
  end

  # vikunja: the v2 helper's group parameter is named `a`, like the
  # `/api/v1` group of its caller, so the prefix scope of `a.Use(...)` reads
  # `/api/v1`. The routes it really guards are found through the group.
  it "guards the routes registered on a handed-in group after its .Use, wherever they are (echo)" do
    routes = <<-GO
      package routes

      import (
      \t"net/http"

      \t"example.com/e/mcp"
      \t"github.com/labstack/echo/v4"
      )

      func auth() echo.MiddlewareFunc {
      \treturn func(next echo.HandlerFunc) echo.HandlerFunc {
      \t\treturn func(c echo.Context) error {
      \t\t\tif c.Request().Header.Get("Authorization") == "" {
      \t\t\t\treturn c.JSON(http.StatusUnauthorized, nil)
      \t\t\t}
      \t\t\treturn next(c)
      \t\t}
      \t}
      }

      func RegisterRoutes(e *echo.Echo) {
      \ta := e.Group("/api/v1")
      \ta.GET("/v1-open", h)
      \tregisterV2(e, e.Group("/api/v2"))
      }

      func registerV2(e *echo.Echo, a *echo.Group) {
      \ta.GET("/early", h)
      \ta.Use(auth())
      \ta.GET("/docs", h)
      \tm := &mcp.Module{}
      \tm.Register(a)
      }
      GO
    mcp = <<-GO
      package mcp

      import "github.com/labstack/echo/v4"

      func (m *Module) Register(g *echo.Group) {
      \tg.POST("/mcp", m.handle)
      }
      GO
    result = router_scope_scan({"go.mod" => "module example.com/e\n", "routes/routes.go" => routes, "mcp/mcp.go" => mcp},
      [{"GET", "/api/v2/docs", "routes/routes.go", %("/docs")}, {"POST", "/api/v2/mcp", "mcp/mcp.go", %("/mcp")},
       {"GET", "/api/v2/early", "routes/routes.go", %("/early")}], "go_echo")
    guarded?(result["GET /api/v2/docs"]).should be_true
    guarded?(result["POST /api/v2/mcp"]).should be_true
    guarded?(result["GET /api/v2/early"]).should be_false
  end

  it "guards a fiber route registered after app.Use on a group created before it" do
    src = <<-GO
      package main

      import (
      \t"github.com/gofiber/fiber/v2"
      \t"github.com/gofiber/fiber/v2/middleware/keyauth"
      )

      func main() {
      \tapp := fiber.New()
      \tapp.Get("/early", func(c *fiber.Ctx) error { return nil })
      \tapi := app.Group("/api")
      \tapp.Use(keyauth.New(keyauth.Config{KeyLookup: "header:x"}))
      \tapi.Get("/late", func(c *fiber.Ctx) error { return nil })
      }
      GO
    result = router_scope_scan({"go.mod" => "module f\n", "main.go" => src},
      [{"GET", "/early", "main.go", %("/early")}, {"GET", "/api/late", "main.go", %("/late")}], "go_fiber")
    guarded?(result["GET /early"]).should be_false
    guarded?(result["GET /api/late"]).should be_true
  end

  it "still guards a subrouter mounted on the guarded router (chi Mount, mux Subrouter)" do
    chi = <<-GO
      package main

      import "github.com/go-chi/chi/v5"

      func adminRouter() chi.Router {
      \ts := chi.NewRouter()
      \ts.Get("/users", h)
      \treturn s
      }

      func main() {
      \tr := chi.NewRouter()
      \tr.Use(RequireAuth)
      \tr.Mount("/admin", adminRouter())
      \tlocal := chi.NewRouter()
      \tlocal.Get("/x", h)
      \tr.Mount("/local", local)
      }
      GO
    result = router_scope_scan({"go.mod" => "module c\n", "main.go" => chi},
      [{"GET", "/admin/users", "main.go", %("/users")}, {"GET", "/local/x", "main.go", %("/x")}], "go_chi")
    guarded?(result["GET /admin/users"]).should be_true
    guarded?(result["GET /local/x"]).should be_true

    mux = <<-GO
      package main

      import "github.com/gorilla/mux"

      func main() {
      \tr := mux.NewRouter()
      \tr.Use(authMiddleware)
      \tapi := r.PathPrefix("/api").Subrouter()
      \tapi.HandleFunc("/users", h)
      }
      GO
    result = router_scope_scan({"go.mod" => "module m\n", "main.go" => mux},
      [{"GET", "/api/users", "main.go", %("/users")}], "go_mux")
    guarded?(result["GET /api/users"]).should be_true
  end

  it "still guards routes another module of the workspace registers" do
    main = GIN_AUTH + <<-GO
      func main() {
      \tr := gin.Default()
      \tr.Use(Auth())
      \tapi.Register(r)
      }
      GO
    api = <<-GO
      package api

      import "github.com/gin-gonic/gin"

      func Register(r *gin.Engine) {
      \tr.GET("/users", func(c *gin.Context) {})
      }
      GO
    result = router_scope_scan({"app/go.mod" => "module example.com/app\n\nrequire example.com/api v0.0.0\n", "app/main.go" => main,
                                "api/go.mod" => "module example.com/api\n", "api/api.go" => api},
      [{"GET", "/users", "api/api.go", %("/users")}], "go_gin")
    guarded?(result["GET /users"]).should be_true
  end

  it "reads every call of a helper in the owner's function, past nested blocks" do
    main = GIN_AUTH + <<-GO
      func main() {
      \tr := gin.Default()
      \tv1 := r.Group("/api")
      \tregister(v1.Group("/a"))
      \tif auth {
      \t\tv1.Use(Auth())
      \t}
      \tregister(v1.Group("/b"))
      }
      GO
    helper = <<-GO
      package main

      import "github.com/gin-gonic/gin"

      func register(g *gin.RouterGroup) {
      \tg.GET("/items", func(c *gin.Context) {})
      }
      GO
    result = router_scope_scan({"go.mod" => GIN_MOD, "main.go" => main, "helper.go" => helper},
      [{"GET", "/api/b/items", "helper.go", %("/items")}], "go_gin")
    guarded?(result["GET /api/b/items"]).should be_true
  end

  it "reads a .Use just above the route across its lines and through a derived group" do
    src = <<-GO
      package main

      func main() {
      \te := echo.New()
      \tpub := e.Group("/pub")
      \tpub.Use(echojwt.WithConfig(echojwt.Config{SigningKey: k,
      \t\tSkipper: skipPublic}))
      \tpub.GET("/feed", h)
      \tv1 := e.Group("/v1")
      \tv1.Use(echojwt.JWT(k))
      \tusers := v1.Group("/users")
      \tusers.GET("/me", h)
      }
      GO
    result = router_scope_scan({"go.mod" => "module e\n", "main.go" => src},
      [{"GET", "/pub/feed", "main.go", %("/feed")}, {"GET", "/v1/users/me", "main.go", %("/me")}], "go_echo")
    guarded?(result["GET /pub/feed"]).should be_false
    guarded?(result["GET /v1/users/me"]).should be_true
  end

  it "guards an echo route registered before e.Use (router-level middleware)" do
    src = <<-GO
      package main

      import (
      \t"github.com/labstack/echo/v4"
      \t"github.com/labstack/echo/v4/middleware"
      )

      func main() {
      \te := echo.New()
      \te.GET("/early", ok)
      \te.Use(middleware.KeyAuth(validate))
      }
      GO
    result = router_scope_scan({"go.mod" => "module e\n", "main.go" => src},
      [{"GET", "/early", "main.go", %("/early")}], "go_echo")
    guarded?(result["GET /early"]).should be_true
  end
end

describe "GoAuthTagger (conditional middleware)" do
  it "reads a soft-auth factory's flag argument" do
    src = <<-GO
      package main

      import (
      \t"net/http"

      \t"github.com/gin-gonic/gin"
      )

      func Auth(required bool) gin.HandlerFunc {
      \treturn func(c *gin.Context) {
      \t\tif c.GetHeader("Authorization") == "" {
      \t\t\tif required {
      \t\t\t\tc.AbortWithStatus(http.StatusUnauthorized)
      \t\t\t}
      \t\t\treturn
      \t\t}
      \t}
      }

      func main() {
      \tr := gin.Default()
      \tsoft := r.Group("/soft")
      \tsoft.Use(Auth(false))
      \tsoft.GET("/tags", func(c *gin.Context) {})
      \thard := r.Group("/hard")
      \thard.Use(Auth(true))
      \thard.GET("/me", func(c *gin.Context) {})
      }
      GO
    result = router_scope_scan({"go.mod" => GIN_MOD, "main.go" => src},
      [{"GET", "/soft/tags", "main.go", "soft.GET"}, {"GET", "/hard/me", "main.go", "hard.GET"}], "go_gin")
    guarded?(result["GET /soft/tags"]).should be_false
    guarded?(result["GET /hard/me"]).should be_true
  end

  it "does not claim an echo middleware whose config sets a Skipper" do
    src = <<-GO
      package main

      import (
      \t"github.com/labstack/echo/v4"
      \t"github.com/labstack/echo/v4/middleware"
      )

      func main() {
      \te := echo.New()
      \tarticles := e.Group("/articles", middleware.KeyAuthWithConfig(middleware.KeyAuthConfig{
      \t\tSkipper: func(c echo.Context) bool {
      \t\t\treturn c.Request().Method == "GET"
      \t\t},
      \t\tValidator: validate,
      \t}))
      \tarticles.GET("", ok)
      \tjwtMw := middleware.JWTWithConfig(middleware.JWTConfig{
      \t\tSkipper:    skipFeed,
      \t\tSigningKey: key,
      \t})
      \tfeed := e.Group("/feed")
      \tfeed.Use(jwtMw)
      \tfeed.GET("", ok)
      \tstrict := e.Group("/strict")
      \tstrict.Use(middleware.KeyAuthWithConfig(middleware.KeyAuthConfig{
      \t\tSkipper:   middleware.DefaultSkipper,
      \t\tValidator: validate,
      \t}))
      \tstrict.GET("", ok)
      }
      GO
    result = router_scope_scan({"go.mod" => "module e\n", "main.go" => src},
      [{"GET", "/articles", "main.go", "articles.GET"}, {"GET", "/feed", "main.go", "feed.GET"},
       {"GET", "/strict", "main.go", "strict.GET"}], "go_echo")
    guarded?(result["GET /articles"]).should be_false
    guarded?(result["GET /feed"]).should be_false
    guarded?(result["GET /strict"]).should be_true
  end
end

# Framework-specific ways of putting a guard in front of routes (#3306).
describe "GoAuthTagger (framework auth registrations)" do
  it "reads PocketBase .Bind(...) on a route and on a group" do
    src = <<-GO
      package apis

      import (
      \t"github.com/pocketbase/pocketbase/apis"
      \t"github.com/pocketbase/pocketbase/tools/router"
      )

      func BindBackupApi(rg *router.RouterGroup[*core.RequestEvent]) {
      \tsub := rg.Group("/backups")
      \tsub.GET("", H).Bind(apis.RequireSuperuserAuth())
      \trg.GET("/first", H)
      \tsg := rg.Group("/sql").Bind(apis.RequireSuperuserAuth())
      \tsg.POST("", H)
      }
      GO
    result = router_scope_scan({"go.mod" => "module p\n", "apis/backup.go" => src},
      [{"GET", "/api/backups", "apis/backup.go", "sub.GET"}, {"GET", "/api/first", "apis/backup.go", %("/first")},
       {"POST", "/api/sql", "apis/backup.go", "sg.POST"}], "go_pocketbase")
    guarded?(result["GET /api/backups"]).should be_true
    guarded?(result["GET /api/first"]).should be_false
    guarded?(result["POST /api/sql"]).should be_true
  end

  it "reads go-zero jwt: / middleware: in .api files and rest.WithJwt in routes.go" do
    api = <<-API
      @server(
      \tprefix: /api/v1
      \tjwt: JwtAuth
      )
      service user-api {
      \t@handler detail
      \tget /users/:id (DetailReq) returns (Resp)
      }

      @server(
      \tmiddleware: AdminCheck
      )
      service user-api {
      \t@handler stats
      \tget /stats returns (Resp)
      }

      service user-api {
      \t@handler health
      \tget /health returns (Resp)
      }
      API
    middleware = <<-GO
      package middleware

      import "net/http"

      type AdminCheckMiddleware struct{}

      func (m *AdminCheckMiddleware) Handle(next http.HandlerFunc) http.HandlerFunc {
      \treturn func(w http.ResponseWriter, r *http.Request) {
      \t\tif r.Header.Get("Authorization") == "" {
      \t\t\tw.WriteHeader(http.StatusUnauthorized)
      \t\t\treturn
      \t\t}
      \t\tnext(w, r)
      \t}
      }
      GO
    routes = <<-GO
      package handler

      func RegisterHandlers(server *rest.Server, serverCtx *svc.ServiceContext) {
      \tserver.AddRoutes(
      \t\t[]rest.Route{
      \t\t\t{Method: http.MethodPut, Path: "/users/:id", Handler: UpdateHandler(serverCtx)},
      \t\t},
      \t\trest.WithJwt(serverCtx.Config.JwtAuth.AccessSecret),
      \t)
      \tserver.AddRoutes(
      \t\t[]rest.Route{
      \t\t\t{Method: http.MethodGet, Path: "/ping", Handler: PingHandler(serverCtx)},
      \t\t},
      \t)
      }
      GO
    files = {"go.mod" => "module z\n", "desc/user.api" => api, "internal/middleware/admincheckmiddleware.go" => middleware,
             "internal/handler/routes.go" => routes}
    result = router_scope_scan(files,
      [{"GET", "/api/v1/users/:id", "desc/user.api", "get /users"}, {"GET", "/stats", "desc/user.api", "get /stats"},
       {"GET", "/health", "desc/user.api", "get /health"}, {"PUT", "/users/:id", "internal/handler/routes.go", %("/users/:id")},
       {"GET", "/ping", "internal/handler/routes.go", %("/ping")}], "go_gozero")
    guarded?(result["GET /api/v1/users/:id"]).should be_true
    guarded?(result["GET /stats"]).should be_true
    guarded?(result["GET /health"]).should be_false
    guarded?(result["PUT /users/:id"]).should be_true
    guarded?(result["GET /ping"]).should be_false
  end

  it "reads Kratos http.Middleware server options for that server's routes only" do
    server = <<-GO
      package main

      import (
      \t"github.com/go-kratos/kratos/v2/middleware/auth/jwt"
      \t"github.com/go-kratos/kratos/v2/transport/http"
      \tv1 "example.com/k/api/v1"
      )

      func main() {
      \thttpSrv := http.NewServer(
      \t\thttp.Address(":8000"),
      \t\thttp.Middleware(jwt.Server(keyFunc)),
      \t)
      \tr := httpSrv.Route("/")
      \tr.POST("/admin/users", h)
      \tv1.RegisterGreeterHTTPServer(httpSrv, svc)
      }
      GO
    pb = <<-GO
      package v1

      func RegisterGreeterHTTPServer(s *http.Server, srv GreeterHTTPServer) {
      \tr := s.Route("/")
      \tr.GET("/hello/{name}", handler(srv))
      }
      GO
    open = <<-GO
      package main

      import "github.com/go-kratos/kratos/v2/transport/http"

      func main() {
      \tsrv := http.NewServer(http.Address(":8001"))
      \tr := srv.Route("/")
      \tr.POST("/open", h)
      }
      GO
    result = router_scope_scan({"go.mod" => "module example.com/k\n", "cmd/app/main.go" => server, "api/v1/greeter_http.pb.go" => pb,
                                "cmd/open/main.go" => open},
      [{"POST", "/admin/users", "cmd/app/main.go", %("/admin/users")}, {"GET", "/hello/{name}", "api/v1/greeter_http.pb.go", %("/hello)},
       {"POST", "/open", "cmd/open/main.go", %("/open")}], "go_kratos")
    guarded?(result["POST /admin/users"]).should be_true
    guarded?(result["GET /hello/{name}"]).should be_true
    guarded?(result["POST /open"]).should be_false
  end

  it "reads GoFrame group.Middleware(...) for the closure's routes and its bound controllers" do
    main = <<-GO
      package main

      import (
      \t"github.com/gogf/gf/v2/frame/g"
      \t"github.com/gogf/gf/v2/net/ghttp"
      )

      type Ctrl struct{}

      func (Ctrl) Profile(ctx context.Context, req *v1.ProfileReq) (*v1.ProfileRes, error) { return nil, nil }

      func (Ctrl) Login(ctx context.Context, req *v1.LoginReq) (*v1.LoginRes, error) { return nil, nil }

      func Auth(r *ghttp.Request) {
      \tif r.Header.Get("Authorization") == "" {
      \t\tr.Response.WriteStatus(401)
      \t\treturn
      \t}
      \tr.Middleware.Next()
      }

      func main() {
      \ts := g.Server()
      \tctrl := Ctrl{}
      \ts.Group("/", func(group *ghttp.RouterGroup) {
      \t\tgroup.Bind(
      \t\t\tctrl.Login,
      \t\t)
      \t\tgroup.Group("/api", func(group *ghttp.RouterGroup) {
      \t\t\tgroup.Middleware(Auth)
      \t\t\tgroup.Bind(
      \t\t\t\tctrl.Profile,
      \t\t\t)
      \t\t\tgroup.ALL("/any", func(r *ghttp.Request) {})
      \t\t})
      \t})
      \ts.BindHandler("/hook", func(r *ghttp.Request) {})
      }
      GO
    api = <<-GO
      package v1

      type ProfileReq struct {
      \tg.Meta `path:"/profile" method:"get"`
      }

      type LoginReq struct {
      \tg.Meta `path:"/login" method:"post"`
      }
      GO
    result = router_scope_scan({"go.mod" => "module f\n", "main.go" => main, "api/v1/user.go" => api},
      [{"GET", "/api/any", "main.go", %("/any")}, {"GET", "/hook", "main.go", %("/hook")},
       {"GET", "/api/profile", "api/v1/user.go", %(path:"/profile")}, {"POST", "/login", "api/v1/user.go", %(path:"/login")}], "go_gf")
    guarded?(result["GET /api/any"]).should be_true
    guarded?(result["GET /hook"]).should be_false
    guarded?(result["GET /api/profile"]).should be_true
    guarded?(result["POST /login"]).should be_false
  end

  it "inherits an enclosing GoFrame closure's middleware for a nested bind, and reads grouped request types" do
    main = <<-GO
      package main

      import "github.com/gogf/gf/v2/net/ghttp"

      type Ctrl struct{}

      func (Ctrl) Profile(ctx context.Context, req *v1.ProfileReq) (*v1.ProfileRes, error) { return nil, nil }

      func Auth(r *ghttp.Request) {
      \tif r.Header.Get("Authorization") == "" {
      \t\tr.SetError(gerror.NewCode(gcode.CodeNotAuthorized, "no token"))
      \t\treturn
      \t}
      \tr.Middleware.Next()
      }

      func Wrap(r *ghttp.Request) {
      \tr.Middleware.Next()
      \tif r.GetError() != nil && gerror.Code(r.GetError()) == gcode.CodeNotAuthorized {
      \t\tr.Response.Write("denied")
      \t}
      }

      func main() {
      \ts.Group("/", func(group *ghttp.RouterGroup) {
      \t\tgroup.Middleware(Auth)
      \t\tgroup.Group("/user", func(group *ghttp.RouterGroup) {
      \t\t\tgroup.Bind(Ctrl{})
      \t\t})
      \t})
      \ts.Group("/open", func(group *ghttp.RouterGroup) {
      \t\tgroup.Middleware(Wrap)
      \t\tgroup.ALL("/x", func(r *ghttp.Request) {})
      \t})
      }
      GO
    api = <<-GO
      package v1

      type (
      \tProfileReq struct {
      \t\tg.Meta `path:"/profile" method:"get"`
      \t}
      )
      GO
    result = router_scope_scan({"go.mod" => "module f\n", "main.go" => main, "api/v1/user.go" => api},
      [{"GET", "/user/profile", "api/v1/user.go", %(path:"/profile")}, {"GET", "/open/x", "main.go", %("/x")}], "go_gf")
    guarded?(result["GET /user/profile"]).should be_true
    guarded?(result["GET /open/x"]).should be_false
  end

  it "reads an aliased Kratos transport and a PocketBase .Bind continued on the next line" do
    kratos = <<-GO
      package main

      import (
      \t"github.com/go-kratos/kratos/v2/middleware/auth/jwt"
      \tkhttp "github.com/go-kratos/kratos/v2/transport/http"
      )

      func main() {
      \tsrv := khttp.NewServer(khttp.Middleware(jwt.Server(keyFunc)))
      \tr := srv.Route("/")
      \tr.POST("/admin", h)
      }
      GO
    result = router_scope_scan({"go.mod" => "module k\n", "main.go" => kratos}, [{"POST", "/admin", "main.go", %("/admin")}], "go_kratos")
    guarded?(result["POST /admin"]).should be_true

    pocketbase = <<-GO
      package apis

      import "github.com/pocketbase/pocketbase/apis"

      func bind(rg *router.RouterGroup[*core.RequestEvent]) {
      \trg.GET("/settings", H).
      \t\tBind(apis.RequireSuperuserAuth())
      }
      GO
    result = router_scope_scan({"go.mod" => "module p\n", "apis/settings.go" => pocketbase},
      [{"GET", "/settings", "apis/settings.go", %("/settings")}], "go_pocketbase")
    guarded?(result["GET /settings"]).should be_true
  end
end
