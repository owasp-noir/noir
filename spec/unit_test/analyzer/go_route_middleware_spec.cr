require "../../spec_helper"
require "../../../src/analyzer/analyzers/go/gin"
require "../../../src/analyzer/analyzers/go/chi"
require "../../../src/analyzer/analyzers/go/echo"
require "../../../src/analyzer/analyzers/go/fiber"
require "../../../src/analyzer/analyzers/go/pocketbase"
require "../../../src/tagger/tagger"

private def go_middleware_rows(klass, source, &)
  dir = File.tempname("go-middleware")
  Dir.mkdir(dir)
  file = File.join(dir, "main.go")
  File.write(file, source)
  locator = CodeLocator.instance
  locator.clear_all
  locator.register_path(file)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(dir)])
  rows = klass.new(options).analyze
  yield rows.to_h { |ep| {ep.url, ep} }
ensure
  CodeLocator.instance.clear_all
  FileUtils.rm_rf(dir) if dir
end

describe "Go route middleware evidence" do
  it "snapshots Gin groups at creation and preserves step order and origin" do
    go_middleware_rows(Analyzer::Go::Gin, <<-GO) do |rows|
      package main
      import "github.com/gin-gonic/gin"
      func main() {
        r := gin.New()
        r.Use(first)
        g := r.Group("/group", second)
        r.Use(rootOnly)
        g.Use(third)
        g.GET("/one", fourth, handler)
        g.Use(tooLate)
        r.GET("/two", handler)
      }
      GO
      row = rows["/group/one"]
      steps = row.details.code_paths.first.route_middleware.not_nil!
      steps.map(&.source).should eq(%w[first second third fourth handler])
      steps.map(&.origin).should eq([:router, :mount, :router, :route, :route])
      steps.select(&.handler_position).map(&.source).should eq(["handler"])
      row.to_json.should_not contain("fourth")
      row.to_yaml.should_not contain("fourth")
      rows["/two"].details.code_paths.first.route_middleware.not_nil!.map(&.source).should eq(%w[first rootOnly handler])
    end
  end

  it "carries the caller's middleware into a Gin builder at its resolved prefix" do
    go_middleware_rows(Analyzer::Go::Gin, <<-GO) do |rows|
      package main
      import "github.com/gin-gonic/gin"
      func main() {
        r := gin.New()
        r.Use(first)
        api := r.Group("/api", second)
        register(api)
      }
      func register(group *gin.RouterGroup) {
        group.Use(third)
        group.GET("/items", fourth, handler)
      }
      GO
      steps = rows["/api/items"].details.code_paths.first.route_middleware.not_nil!
      steps.map(&.source).should eq(%w[first second third fourth handler])
      steps.first(2).map(&.origin).should eq([:mount, :mount])
    end
  end

  it "prepends chi mount middleware to the child router's own chain" do
    go_middleware_rows(Analyzer::Go::Chi, <<-GO) do |rows|
      package main
      import "github.com/go-chi/chi/v5"
      import "net/http"
      func main() {
        r := chi.NewRouter()
        r.Use(parent)
        r.Mount("/api", childRoutes())
      }
      func childRoutes() http.Handler {
        s := chi.NewRouter()
        s.Use(child)
        s.Get("/item", handler)
        return s
      }
      GO
      steps = rows["/api/item"].details.code_paths.first.route_middleware.not_nil!
      steps.map(&.source).should eq(%w[parent child handler])
      steps.first.origin.should eq(:mount)
    end
  end

  it "places Echo Pre first, follows late instance Use, and snapshots group middleware" do
    go_middleware_rows(Analyzer::Go::Echo, <<-GO) do |rows|
      package main
      import "github.com/labstack/echo/v4"
      func main() {
        e := echo.New()
        e.Use(root)
        g := e.Group("/g", groupStep)
        g.GET("/one", handler, routeStep)
        g.Use(tooLate)
        e.Pre(pre)
        e.Use(live)
      }
      GO
      steps = rows["/g/one"].details.code_paths.first.route_middleware.not_nil!
      steps.map(&.source).should eq(%w[pre root live groupStep routeStep handler])
      steps.last.handler_position.should be_true
    end
  end

  it "records PocketBase Bind calls on the registered route in order" do
    go_middleware_rows(Analyzer::Go::Pocketbase, <<-GO) do |rows|
      package main
      import "github.com/pocketbase/pocketbase/core"
      func register(e *core.ServeEvent) {
        e.Router.GET("/one", handler).
          Bind(first).
          Bind(second)
        e.Router.GET("/two", handler)
      }
      GO
      steps = rows["/one"].details.code_paths.first.route_middleware.not_nil!
      steps.map(&.source).should eq(%w[first second handler])
      steps.map(&.origin).should eq([:bind, :bind, :route])
      rows["/two"].details.code_paths.first.route_middleware.not_nil!.map(&.source).should eq(["handler"])
    end
  end

  it "uses the Fiber v2 path stack for siblings and leaves prior routes alone" do
    go_middleware_rows(Analyzer::Go::Fiber, <<-GO) do |rows|
      package main
      import "github.com/gofiber/fiber/v2"
      func main() {
        app := fiber.New()
        app.Get("/api/early", handler)
        a := app.Group("/api", first)
        a.Use(second)
        app.Get("/api/sibling", handler)
        app.Get("/elsewhere", handler)
      }
      GO
      rows["/api/early"].details.code_paths.first.route_middleware.not_nil!.map(&.source).should eq(["handler"])
      rows["/api/sibling"].details.code_paths.first.route_middleware.not_nil!.map(&.source).should eq(%w[first second handler])
      rows["/elsewhere"].details.code_paths.first.route_middleware.not_nil!.map(&.source).should eq(["handler"])
    end
  end
end

describe GoAuthTagger do
  it "judges recorded middleware when the registration source is unavailable" do
    file = File.join(File.tempname("go-middleware"), "main.go")
    location = PathInfo.new(file, 1)
    location.route_middleware = [RouteMiddleware.new("AuthRequired", file)]
    details = Details.new(location)
    details.technology = "go_gin"
    endpoint = Endpoint.new("/private", "GET", details)
    result = GoAuthTagger.new(create_test_options).perform([endpoint]).first
    result.tags.map(&.description).should eq(["Protected by Go AuthRequired middleware"])
    result.resolution.should eq({"guard" => "heuristic"})
  end
end
