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
