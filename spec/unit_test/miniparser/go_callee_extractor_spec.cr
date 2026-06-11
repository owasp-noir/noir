require "../../spec_helper"
require "../../../src/miniparsers/go_callee_extractor"

describe Noir::GoCalleeExtractor do
  describe ".collect_function_bodies" do
    it "indexes every top-level function declaration by name" do
      source = <<-GO
        package handlers

        func Show(c *gin.Context) {
          c.JSON(200, "ok")
        }

        func Update(c *gin.Context) {
          c.JSON(200, "ok")
        }

        func helper() {}
        GO

      bodies = Noir::GoCalleeExtractor.collect_function_bodies(source, "handlers.go")
      bodies.keys.sort!.should eq(["Show", "Update", "helper"])
      bodies["Show"].file_path.should eq("handlers.go")
      bodies["Show"].source.should contain("c.JSON(200, \"ok\")")
    end

    it "first definition wins when a name is declared twice" do
      # Go itself rejects this at build time, but the extractor is
      # asked to be resilient against malformed snippets.
      source = <<-GO
        package x
        func Foo() { return }
        func Foo() { return }
        GO

      bodies = Noir::GoCalleeExtractor.collect_function_bodies(source, "x.go")
      bodies.size.should eq(1)
      bodies.has_key?("Foo").should be_true
    end

    it "returns an empty map for source with no functions" do
      Noir::GoCalleeExtractor.collect_function_bodies("package x\n", "x.go").should be_empty
    end

    it "records the 0-based start row of the func keyword" do
      source = <<-GO
        package handlers


        func Show(c *gin.Context) {
          c.JSON(200, "ok")
        }
        GO

      bodies = Noir::GoCalleeExtractor.collect_function_bodies(source, "handlers.go")
      bodies["Show"].start_row.should eq(3)
    end
  end

  describe ".package_function_bodies" do
    it "groups per-file function bodies by directory" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "app/handlers/users.go"  => "package handlers\nfunc UserShow() {}\n",
        "app/handlers/orders.go" => "package handlers\nfunc OrderList() {}\n",
        "app/server/main.go"     => "package server\nfunc Boot() {}\n",
      })

      bodies.keys.sort!.should eq(["app/handlers", "app/server"])
      bodies["app/handlers"].keys.sort!.should eq(["OrderList", "UserShow"])
      bodies["app/server"].keys.should eq(["Boot"])
    end

    it "earlier file wins on name collisions within a directory" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
        "pkg/b.go" => "package p\nfunc Handler() {}\n",
      })

      pkg = bodies["pkg"]
      pkg.size.should eq(1)
      # First file in iteration order wins so cross-file lookups are
      # deterministic.
      pkg["Handler"].file_path.should eq("pkg/a.go")
    end

    it "omits directories whose files declared no functions" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "pkg/empty.go" => "package p\n",
      })
      bodies.should be_empty
    end
  end

  describe ".package_function_bodies_if" do
    it "returns an empty map immediately when enabled=false" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies_if(false, {
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
      })
      bodies.should be_empty
    end

    it "delegates to package_function_bodies when enabled=true" do
      bodies = Noir::GoCalleeExtractor.package_function_bodies_if(true, {
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
      })
      bodies["pkg"]["Handler"].file_path.should eq("pkg/a.go")
    end
  end

  describe ".function_bodies_for_directory" do
    it "returns the body map for the requested directory" do
      package_bodies = Noir::GoCalleeExtractor.package_function_bodies({
        "pkg/a.go" => "package p\nfunc Handler() {}\n",
      })
      Noir::GoCalleeExtractor.function_bodies_for_directory(package_bodies, "pkg")
        .keys.should eq(["Handler"])
    end

    it "returns an empty map for an unknown directory rather than nil" do
      Noir::GoCalleeExtractor.function_bodies_for_directory(
        Hash(String, Hash(String, Noir::GoCalleeExtractor::FunctionBody)).new,
        "nowhere"
      ).should be_empty
    end
  end

  describe ".callees_for_routes" do
    it "returns an empty map when no route rows were supplied" do
      Noir::GoCalleeExtractor.callees_for_routes(
        "package x\n", "x.go", Set(Int32).new, Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      ).should be_empty
    end

    it "walks an inline closure handler and reports its callees" do
      source = <<-GO
        package main

        func register(app *gin.Engine) {
          app.GET("/users", func(c *gin.Context) {
            user := lookupUser(c)
            c.JSON(200, user)
          })
        }
        GO

      # The `app.GET(...)` call sits on the row that has `app.GET`.
      # Find it dynamically — exact row depends on the heredoc.
      target_row = source.lines.index!(&.includes?("app.GET("))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("lookupUser")
      # c.JSON is a method on the framework receiver — it's a useful
      # signal so it must be retained (only builtins / primitives are
      # filtered).
      names.should contain("c.JSON")
    end

    it "filters Go builtins out of the callee list" do
      source = <<-GO
        package main

        func register(app *gin.Engine) {
          app.GET("/items", func(c *gin.Context) {
            n := len(items)
            out := make([]int, 0)
            c.JSON(200, n)
          })
        }
        GO

      target_row = source.lines.index!(&.includes?("app.GET("))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row]?.try(&.map(&.[0])) || [] of String

      names.should_not contain("len")
      names.should_not contain("make")
      names.should contain("c.JSON")
    end

    it "resolves a same-file identifier handler against local functions" do
      source = <<-GO
        package main

        func showUser(c *gin.Context) {
          user := lookupUser(c)
          c.JSON(200, user)
        }

        func register(app *gin.Engine) {
          app.GET("/users", showUser)
        }
        GO

      target_row = source.lines.index!(&.includes?("app.GET("))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("lookupUser")
      names.should contain("c.JSON")
    end

    it "resolves mux builder-chain HandlerFunc handlers" do
      source = <<-GO
        package main

        func createUser(w http.ResponseWriter, r *http.Request) {
          user := saveUser(r)
          w.Write([]byte(user))
        }

        func register(r *mux.Router) {
          r.Methods("POST").
            Path("/users").
            HandlerFunc(createUser)
        }
        GO

      target_row = source.lines.index!(&.includes?("r.Methods(\"POST\")"))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("saveUser")
      names.should contain("w.Write")
    end

    it "unwraps http.HandlerFunc wrappers in mux Handler chains" do
      source = <<-GO
        package main

        func createUser(w http.ResponseWriter, r *http.Request) {
          user := saveUser(r)
          w.Write([]byte(user))
        }

        func register(r *mux.Router) {
          r.Path("/users").
            Methods("POST").
            Handler(http.HandlerFunc(createUser))
        }
        GO

      target_row = source.lines.index!(&.includes?("r.Path(\"/users\")"))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("saveUser")
      names.should contain("w.Write")
    end

    it "unwraps variadic append handler lists and resolves the actual handler" do
      source = <<-GO
        package main

        func createUser(c context.Context, ctx *app.RequestContext) {
          user := saveUser(ctx)
          ctx.JSON(200, user)
        }

        func register(app *server.Hertz) {
          app.GET("/users", append(routeMw(), createUser)...)
        }
        GO

      target_row = source.lines.index!(&.includes?("app.GET("))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("saveUser")
      names.should contain("ctx.JSON")
    end

    it "resolves imported selector handlers when package functions are indexed" do
      source = <<-GO
        package main

        import feed "github.com/acme/app/handlers/feed"

        func register(app *server.Hertz) {
          app.GET("/feed", append(routeMw(), feed.Feed)...)
        }
        GO
      feed_source = <<-GO
        package feed

        func Feed(c context.Context, ctx *app.RequestContext) {
          item := buildFeed(ctx)
          ctx.JSON(200, item)
        }

        func buildFeed(ctx *app.RequestContext) string {
          return ""
        }
        GO

      target_row = source.lines.index!(&.includes?("app.GET("))
      imported_functions = {
        "github.com/acme/app/handlers/feed" => Noir::GoCalleeExtractor.collect_function_bodies(feed_source, "handlers/feed/feed.go"),
      }
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source,
        "router/feed.go",
        Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        imported_functions: imported_functions
      )
      names = callees[target_row].map(&.[0])

      names.should contain("buildFeed")
      names.should contain("ctx.JSON")
    end

    it "prefers imported selector handlers over same-package methods with the same name" do
      source = <<-GO
        package main

        import api "github.com/acme/app/api"

        type LocalController struct{}

        func (lc *LocalController) Get(c *fiber.Ctx) error {
          localOnly(c)
          return c.SendStatus(200)
        }

        func register(app *fiber.App) {
          app.Get("/items", api.Get)
        }
        GO
      api_source = <<-GO
        package api

        func Get(c *fiber.Ctx) error {
          item := importedOnly(c)
          return c.JSON(item)
        }
        GO

      target_row = source.lines.index!(&.includes?("app.Get("))
      imported_functions = {
        "github.com/acme/app/api" => Noir::GoCalleeExtractor.collect_function_bodies(api_source, "api/handler.go"),
      }
      external_methods = Noir::GoCalleeExtractor.collect_method_bodies(source, "router.go")
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source,
        "router.go",
        Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        external_methods,
        imported_functions: imported_functions
      )
      names = callees[target_row].map(&.[0])

      names.should contain("importedOnly")
      names.should contain("c.JSON")
      names.should_not contain("localOnly")
      names.should_not contain("c.SendStatus")
    end

    it "walks every handler candidate in a route chain" do
      source = <<-GO
        package main

        func audit(c *fiber.Ctx) error {
          auditRequest(c)
          return c.Next()
        }

        func show(c *fiber.Ctx) error {
          user := loadUser(c)
          return c.JSON(user)
        }

        func register(app *fiber.App) {
          app.Get("/users", audit, show)
        }
        GO

      target_row = source.lines.index!(&.includes?("app.Get("))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source, "main.go", Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )
      names = callees[target_row].map(&.[0])

      names.should contain("auditRequest")
      names.should contain("c.Next")
      names.should contain("loadUser")
      names.should contain("c.JSON")
    end

    it "resolves imported selector handler factories without unwrapping their arguments" do
      source = <<-GO
        package main

        import handlers "github.com/acme/app/handlers"

        func register(app *fiber.App) {
          app.Get("/books", handlers.GetBooks(service))
        }
        GO
      handlers_source = <<-GO
        package handlers

        func GetBooks(service BooksService) fiber.Handler {
          return func(c *fiber.Ctx) error {
            books := service.List(c)
            return c.JSON(books)
          }
        }
        GO

      target_row = source.lines.index!(&.includes?("app.Get("))
      imported_functions = {
        "github.com/acme/app/handlers" => Noir::GoCalleeExtractor.collect_function_bodies(handlers_source, "handlers/books.go"),
      }
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source,
        "router.go",
        Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        imported_functions: imported_functions
      )
      names = callees[target_row].map(&.[0])

      names.should contain("service.List")
      names.should contain("c.JSON")
    end

    it "resolves receiver method handlers created by imported constructors" do
      source = <<-GO
        package main

        import api "github.com/acme/app/api"

        func register(app *fiber.App) {
          handler := api.NewHandler(service)
          app.Get("/products", handler.Get)
        }
        GO
      api_source = <<-GO
        package api

        type Handler struct {
          service ProductService
        }

        func NewHandler(service ProductService) *Handler {
          return &Handler{service: service}
        }

        func (h *Handler) Get(c *fiber.Ctx) error {
          product := h.service.Get(c.Params("code"))
          return c.JSON(product)
        }
        GO

      target_row = source.lines.index!(&.includes?("app.Get("))
      imported_functions = {
        "github.com/acme/app/api" => Noir::GoCalleeExtractor.collect_function_bodies(api_source, "api/handler.go"),
      }
      imported_methods = {
        "github.com/acme/app/api" => Noir::GoCalleeExtractor.collect_method_bodies(api_source, "api/handler.go"),
      }
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source,
        "router.go",
        Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        imported_functions: imported_functions,
        imported_methods: imported_methods
      )
      names = callees[target_row].map(&.[0])

      names.should contain("h.service.Get")
      names.should contain("c.Params")
      names.should contain("c.JSON")
    end

    it "prefers imported receiver method handlers over same-package methods with the same name" do
      source = <<-GO
        package main

        import api "github.com/acme/app/api"

        type LocalController struct{}

        func (lc *LocalController) Show(c *fiber.Ctx) error {
          localShow(c)
          return c.SendStatus(200)
        }

        func register(app *fiber.App) {
          controller := api.NewController(service)
          app.Get("/items", controller.Show)
        }
        GO
      api_source = <<-GO
        package api

        type Controller struct {
          service Service
        }

        func NewController(service Service) *Controller {
          return &Controller{service: service}
        }

        func (c *Controller) Show(ctx *fiber.Ctx) error {
          item := importedShow(ctx)
          return ctx.JSON(item)
        }
        GO

      target_row = source.lines.index!(&.includes?("app.Get("))
      imported_functions = {
        "github.com/acme/app/api" => Noir::GoCalleeExtractor.collect_function_bodies(api_source, "api/controller.go"),
      }
      imported_methods = {
        "github.com/acme/app/api" => Noir::GoCalleeExtractor.collect_method_bodies(api_source, "api/controller.go"),
      }
      external_methods = Noir::GoCalleeExtractor.collect_method_bodies(source, "router.go")
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source,
        "router.go",
        Set{target_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
        external_methods,
        imported_functions: imported_functions,
        imported_methods: imported_methods
      )
      names = callees[target_row].map(&.[0])

      names.should contain("importedShow")
      names.should contain("ctx.JSON")
      names.should_not contain("localShow")
      names.should_not contain("c.SendStatus")
    end

    it "keeps unresolved imported handler references as callee signals" do
      source = <<-GO
        package main

        import "net/http/pprof"

        func register(r chi.Router) {
          r.HandleFunc("/pprof", pprof.Index)
          r.Handle("/pprof/goroutine", pprof.Handler("goroutine"))
        }
        GO

      first_row = source.lines.index!(&.includes?("r.HandleFunc("))
      second_row = source.lines.index!(&.includes?("r.Handle("))
      callees = Noir::GoCalleeExtractor.callees_for_routes(
        source,
        "profiler.go",
        Set{first_row, second_row},
        Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
      )

      callees[first_row].map(&.[0]).should contain("pprof.Index")
      callees[second_row].map(&.[0]).should contain("pprof.Handler")
    end
  end
end
