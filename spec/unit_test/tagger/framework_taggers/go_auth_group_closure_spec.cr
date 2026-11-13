require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Write `files` to a temp tree, run GoAuthTagger on one endpoint per route
# ({method, url, file, text on the route's line}) and return them keyed
# "METHOD url".
private def closure_scan(files : Hash(String, String), routes : Array({String, String, String, String})) : Hash(String, Endpoint)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("go_group_closure")
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
    details.technology = "go_fiber"
    Endpoint.new(url, method, [] of Param, details)
  end
  tagged = GoAuthTagger.new(options).perform(endpoints)
  FileUtils.rm_rf(tmpdir)
  tagged.to_h { |endpoint| {"#{endpoint.method} #{endpoint.url}", endpoint} }
end

private def closure_guarded?(endpoint : Endpoint) : Bool
  endpoint.tags.any? { |tag| tag.name == "auth" || tag.name == "authz" }
end

FIBER_MOD = "module example.com/app\n\nrequire github.com/gofiber/fiber/v2 v2.52.13\n"

# penguin-statistics' shape: groups built once in `svr`, wrapped in project
# types, and registered on by type from controller packages fx invokes.
TYPED_GROUPS = <<-GO
  package svr

  import "github.com/gofiber/fiber/v2"

  type V2 struct {
  \tfiber.Router
  }

  type Admin struct {
  \tfiber.Router
  }

  type Meta struct {
  \tfiber.Router
  }

  func CreateEndpointGroups(app *fiber.App) (*V2, *Admin, *Meta) {
  \tv2 := app.Group("/api/v2", func(c *fiber.Ctx) error {
  \t\tc.Set("X-Api-Version", "2")
  \t\treturn c.Next()
  \t})

  \tadmin := app.Group("/api/admin", func(c *fiber.Ctx) error {
  \t\tkey := c.Get(fiber.HeaderAuthorization)
  \t\tif key == "" {
  \t\t\treturn c.SendStatus(fiber.StatusUnauthorized)
  \t\t}
  \t\treturn c.Next()
  \t})

  \tmeta := app.Group("/api/_")

  \treturn &V2{Router: v2}, &Admin{Router: admin}, &Meta{Router: meta}
  }
  GO

TYPED_CONTROLLERS = <<-GO
  package meta

  import "example.com/app/internal/server/svr"

  func RegisterAdmin(admin *svr.Admin, c AdminController) {
  \tadmin.Post("/save", c.Save)
  }

  func RegisterMeta(meta *svr.Meta, c Meta) {
  \tmeta.Get("/health", c.Health)
  }

  func RegisterV2(v2 *svr.V2, c Item) {
  \tv2.Get("/items", c.List)
  }
  GO

describe "GoAuthTagger (inline group middleware closures)" do
  it "carries a wrapped group's refusing closure to the routes registered on its type" do
    result = closure_scan({
      "go.mod"                             => FIBER_MOD,
      "internal/server/svr/versioning.go"  => TYPED_GROUPS,
      "internal/controller/meta/routes.go" => TYPED_CONTROLLERS,
    }, [
      {"POST", "/api/admin/save", "internal/controller/meta/routes.go", %("/save")},
      {"GET", "/api/_/health", "internal/controller/meta/routes.go", %("/health")},
      {"GET", "/api/v2/items", "internal/controller/meta/routes.go", %("/items")},
    ])
    closure_guarded?(result["POST /api/admin/save"]).should be_true
    result["POST /api/admin/save"].tags.find!(&.name.==("auth")).description.should contain("inline group closure")
    # A closure that only sets a header, and a group with none.
    closure_guarded?(result["GET /api/v2/items"]).should be_false
    closure_guarded?(result["GET /api/_/health"]).should be_false
  end

  it "guards a same-file group's routes with its refusing closure, not a sibling group's" do
    src = <<-GO
      package main

      import "github.com/gofiber/fiber/v2"

      func main() {
      \tapp := fiber.New()
      \tadmin := app.Group("/admin", func(c *fiber.Ctx) error {
      \t\tif c.Get("X-Token") == "" {
      \t\t\treturn fiber.ErrUnauthorized
      \t\t}
      \t\treturn c.Next()
      \t})
      \tadmin.Get("/stats", h)
      \tpub := app.Group("/pub")
      \tpub.Get("/items", h)
      }
      GO
    result = closure_scan({"go.mod" => FIBER_MOD, "main.go" => src}, [
      {"GET", "/admin/stats", "main.go", %("/stats")},
      {"GET", "/pub/items", "main.go", %("/items")},
    ])
    closure_guarded?(result["GET /admin/stats"]).should be_true
    closure_guarded?(result["GET /pub/items"]).should be_false
  end

  it "does not count a closure that never refuses the request" do
    src = <<-GO
      package main

      import (
      \t"log"

      \t"github.com/gofiber/fiber/v2"
      )

      func main() {
      \tapp := fiber.New()
      \tadmin := app.Group("/admin", func(c *fiber.Ctx) error {
      \t\tif c.Get("Authorization") == "" {
      \t\t\tlog.Println("anonymous admin request")
      \t\t}
      \t\treturn c.Next()
      \t})
      \tadmin.Get("/stats", h)
      }
      GO
    result = closure_scan({"go.mod" => FIBER_MOD, "main.go" => src}, [{"GET", "/admin/stats", "main.go", %("/stats")}])
    closure_guarded?(result["GET /admin/stats"]).should be_false
  end

  # The analyzer leaves a wrapper built from two groups unprefixed, so its
  # routes never fall under the guarded group's path.
  it "does not guard the routes of a wrapper built from two groups" do
    groups = <<-GO
      package svr

      import "github.com/gofiber/fiber/v2"

      type Legacy struct {
      \tfiber.Router
      }

      func Create(app *fiber.App) (*Legacy, *Legacy) {
      \ta := app.Group("/legacy/a", func(c *fiber.Ctx) error {
      \t\tif c.Get("X-Token") == "" {
      \t\t\treturn fiber.ErrUnauthorized
      \t\t}
      \t\treturn c.Next()
      \t})
      \tb := app.Group("/legacy/b")
      \treturn &Legacy{Router: a}, &Legacy{Router: b}
      }
      GO
    routes = <<-GO
      package v2

      import "example.com/app/internal/server/svr"

      func RegisterLegacy(legacy *svr.Legacy) {
      \tlegacy.Get("/old", h)
      }
      GO
    result = closure_scan({
      "go.mod"                        => FIBER_MOD,
      "internal/server/svr/groups.go" => groups,
      "internal/controller/v2/old.go" => routes,
    }, [{"GET", "/old", "internal/controller/v2/old.go", %("/old")}])
    closure_guarded?(result["GET /old"]).should be_false
  end
end
