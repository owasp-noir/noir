require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/go/group_scope"

# `GoRouteGroupScope` is a mixin with no `extend self`, so exercising it
# needs a host. This mirrors how `go_auth` / `go_security` include it.
private class GroupScopeHost
  include GoRouteGroupScope

  # Every `.Use(...)` in `content`, as {line, scope}. This is the exact
  # shape both real taggers build their guarded-prefix list from.
  def uses(content : String) : Array(Tuple(String, GoRouteGroupScope::Scope))
    found = [] of Tuple(String, GoRouteGroupScope::Scope)
    each_group_scoped_line(content) do |stripped, scopes|
      if scope = resolve_use_scope(stripped, scopes)
        found << {stripped, scope}
      end
    end
    found
  end

  # Just the resolved prefixes, for the common assertion.
  def use_prefixes(content : String) : Array(String)
    uses(content).map { |(_, scope)| scope[:prefix] }
  end

  def use_kinds(content : String) : Array(GoRouteGroupScope::ScopeKind)
    uses(content).map { |(_, scope)| scope[:kind] }
  end

  def covers?(prefix : String, url : String) : Bool
    prefix_covers?(prefix, url)
  end
end

describe GoRouteGroupScope do
  host = GroupScopeHost.new

  describe ".join_prefix" do
    it "prefixes a bare segment with a slash" do
      GoRouteGroupScope.join_prefix("", "/web").should eq("/web")
    end

    it "joins a base and a segment that has no leading slash" do
      GoRouteGroupScope.join_prefix("/api", "v1").should eq("/api/v1")
    end

    it "collapses the duplicate slash between base and segment" do
      GoRouteGroupScope.join_prefix("/api", "/v1").should eq("/api/v1")
    end

    it "collapses repeated inner slashes" do
      GoRouteGroupScope.join_prefix("/api//", "//v1").should eq("/api/v1")
    end

    it "returns the root when both parts are empty" do
      GoRouteGroupScope.join_prefix("", "").should eq("/")
    end

    it "returns the root when the base is already root and the segment is empty" do
      GoRouteGroupScope.join_prefix("/", "").should eq("/")
    end

    it "drops a trailing slash on the segment" do
      GoRouteGroupScope.join_prefix("/api", "v1/").should eq("/api/v1")
    end
  end

  describe "#prefix_covers?" do
    it "treats the root prefix as covering every url" do
      host.covers?("/", "/anything/at/all").should be_true
    end

    it "covers a url equal to the prefix" do
      host.covers?("/web", "/web").should be_true
    end

    it "covers a url nested under the prefix" do
      host.covers?("/web", "/web/login").should be_true
    end

    it "respects segment boundaries so /web does not cover /website" do
      host.covers?("/web", "/website").should be_false
    end

    it "does not cover an unrelated url" do
      host.covers?("/api", "/admin/users").should be_false
    end
  end

  describe GoRouteGroupScope::Scopes do
    it "reports the global scope at file scope" do
      scopes = GoRouteGroupScope::Scopes.new
      scopes.current.should eq(GoRouteGroupScope::GLOBAL_SCOPE)
    end

    it "falls back to the current scope for an untracked receiver" do
      scopes = GoRouteGroupScope::Scopes.new
      scopes.receiver("someRandomVar").should eq(GoRouteGroupScope::GLOBAL_SCOPE)
    end

    it "falls back to the current scope for a nil receiver" do
      scopes = GoRouteGroupScope::Scopes.new
      scopes.receiver(nil).should eq(GoRouteGroupScope::GLOBAL_SCOPE)
    end

    it "extends a known scope with a literal segment" do
      scopes = GoRouteGroupScope::Scopes.new
      extended = scopes.extend({kind: GoRouteGroupScope::ScopeKind::Group, prefix: "/api"}, "v1")
      extended[:kind].should eq(GoRouteGroupScope::ScopeKind::Group)
      extended[:prefix].should eq("/api/v1")
    end

    it "extends the global scope into a group" do
      scopes = GoRouteGroupScope::Scopes.new
      extended = scopes.extend(GoRouteGroupScope::GLOBAL_SCOPE, "/api")
      extended[:kind].should eq(GoRouteGroupScope::ScopeKind::Group)
      extended[:prefix].should eq("/api")
    end

    it "keeps an unresolvable base unresolvable even under a literal segment" do
      scopes = GoRouteGroupScope::Scopes.new
      extended = scopes.extend(GoRouteGroupScope::UNKNOWN_SCOPE, "/v1")
      extended[:kind].should eq(GoRouteGroupScope::ScopeKind::Unknown)
    end
  end

  describe "#each_group_scoped_line / #resolve_use_scope" do
    it "yields no use scope for a file that registers no middleware" do
      content = <<-GO
        func main() {
          r := gin.Default()
          r.GET("/ping", pong)
        }
        GO

      host.uses(content).should be_empty
    end

    it "resolves an engine-level Use to the global scope" do
      content = <<-GO
        func main() {
          r := gin.Default()
          r.Use(authMiddleware())
          r.GET("/ping", pong)
        }
        GO

      scopes = host.uses(content)
      scopes.size.should eq(1)
      scopes[0][1][:kind].should eq(GoRouteGroupScope::ScopeKind::Global)
      scopes[0][1][:prefix].should eq("/")
    end

    it "resolves a Use on an assignment group to that group's prefix" do
      content = <<-GO
        func main() {
          r := gin.Default()
          api := r.Group("/api")
          api.Use(authMiddleware())
        }
        GO

      host.use_prefixes(content).should eq(["/api"])
    end

    it "resolves a Use on a nested assignment group to the composed prefix" do
      content = <<-GO
        func main() {
          r := gin.Default()
          api := r.Group("/api")
          v1 := api.Group("/v1")
          v1.Use(authMiddleware())
        }
        GO

      host.use_prefixes(content).should eq(["/api/v1"])
    end

    # The regression this module exists for: modelling assignment groups
    # with a push/pop stack made siblings accumulate into "/api/admin".
    it "keeps sibling assignment groups independent instead of accumulating" do
      content = <<-GO
        func main() {
          r := gin.Default()
          api := r.Group("/api")
          admin := r.Group("/admin")
          api.Use(apiAuth())
          admin.Use(adminAuth())
        }
        GO

      host.use_prefixes(content).should eq(["/api", "/admin"])
    end

    it "resolves a Use inside a closure group to the closure's prefix" do
      content = <<-GO
        func main() {
          r := chi.NewRouter()
          r.Route("/api", func(r chi.Router) {
            r.Use(authMiddleware)
            r.Get("/users", listUsers)
          })
        }
        GO

      host.use_prefixes(content).should eq(["/api"])
    end

    it "retires a closure group once its braces unwind" do
      content = <<-GO
        func main() {
          r := chi.NewRouter()
          r.Route("/api", func(r chi.Router) {
            r.Use(authMiddleware)
          })
          r.Use(globalMiddleware)
        }
        GO

      host.use_prefixes(content).should eq(["/api", "/"])
      host.use_kinds(content).last.should eq(GoRouteGroupScope::ScopeKind::Global)
    end

    it "composes nested closure groups" do
      content = <<-GO
        func main() {
          r := chi.NewRouter()
          r.Route("/api", func(r chi.Router) {
            r.Route("/v1", func(r chi.Router) {
              r.Use(authMiddleware)
            })
          })
        }
        GO

      host.use_prefixes(content).should eq(["/api/v1"])
    end

    it "resolves a chained Group(...).Use(...) without an intermediate variable" do
      content = <<-GO
        func main() {
          r := gin.Default()
          r.Group("/api").Use(authMiddleware())
        }
        GO

      host.use_prefixes(content).should eq(["/api"])
    end

    it "resolves a chained Use on a group variable to the composed prefix" do
      content = <<-GO
        func main() {
          r := gin.Default()
          api := r.Group("/api")
          api.Group("/v1").Use(authMiddleware())
        }
        GO

      host.use_prefixes(content).should eq(["/api/v1"])
    end

    it "resolves Party and PartyFunc groups (iris)" do
      content = <<-GO
        func main() {
          app := iris.New()
          admin := app.Party("/admin")
          admin.Use(basicAuth)
        }
        GO

      host.use_prefixes(content).should eq(["/admin"])
    end

    it "resolves Pre as a middleware registration (echo)" do
      content = <<-GO
        func main() {
          e := echo.New()
          g := e.Group("/api")
          g.Pre(middleware.AddTrailingSlash())
        }
        GO

      host.use_prefixes(content).should eq(["/api"])
    end

    # A group whose path is not a literal is genuinely unknowable to a
    # line scanner. Collapsing it to Global would tag every endpoint —
    # including the explicitly public ones — as guarded.
    it "marks an assignment group with a non-literal path as Unknown, not Global" do
      content = <<-GO
        func main() {
          r := gin.Default()
          api := r.Group(cfg.APIBase + "/v1")
          api.Use(authMiddleware())
        }
        GO

      host.use_kinds(content).should eq([GoRouteGroupScope::ScopeKind::Unknown])
    end

    it "marks a closure group with a non-literal path as Unknown" do
      content = <<-GO
        func main() {
          r := chi.NewRouter()
          r.Route(basePath, func(r chi.Router) {
            r.Use(authMiddleware)
          })
        }
        GO

      host.use_kinds(content).should eq([GoRouteGroupScope::ScopeKind::Unknown])
    end

    it "marks a chained Use on a non-literal group as Unknown" do
      content = <<-GO
        func main() {
          r := gin.Default()
          r.Group(cfg.Base).Use(authMiddleware())
        }
        GO

      host.use_kinds(content).should eq([GoRouteGroupScope::ScopeKind::Unknown])
    end

    it "keeps a literal child of an unknown parent unknown" do
      content = <<-GO
        func main() {
          r := gin.Default()
          api := r.Group(cfg.Base)
          v1 := api.Group("/v1")
          v1.Use(authMiddleware())
        }
        GO

      host.use_kinds(content).should eq([GoRouteGroupScope::ScopeKind::Unknown])
    end

    # `admin := r.Group("/admin", func(c *gin.Context) {...})` is both a
    # closure group and an assignment. Resolving the assignment against
    # the already-pushed closure frame would fold the prefix in twice.
    it "does not double-count a line that is both a closure and an assignment group" do
      content = <<-GO
        func main() {
          r := gin.Default()
          admin := r.Group("/admin", func(c *gin.Context) {
            c.Next()
          })
          admin.Use(adminAuth())
        }
        GO

      host.use_prefixes(content).should eq(["/admin"])
    end

    it "resolves a Use on a group declared with = rather than :=" do
      content = <<-GO
        func register(r *gin.Engine) {
          var api *gin.RouterGroup
          api = r.Group("/api")
          api.Use(authMiddleware())
        }
        GO

      host.use_prefixes(content).should eq(["/api"])
    end

    it "handles an empty group path as the root prefix" do
      content = <<-GO
        func main() {
          r := gin.Default()
          root := r.Group("")
          root.Use(authMiddleware())
        }
        GO

      host.use_prefixes(content).should eq(["/"])
    end

    it "yields every line of the file, stripped" do
      content = "package main\n\n  func main() {}\n"
      seen = [] of String
      host.each_group_scoped_line(content) { |stripped, _| seen << stripped }
      seen.should eq(["package main", "", "func main() {}"])
    end

    it "handles empty content without raising" do
      host.uses("").should be_empty
    end
  end
end
