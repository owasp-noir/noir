require "../../../spec_helper"
require "../../../../src/tagger/tagger"

private def structural_scope_endpoint(body : String, framework = "gin", gate : String? = nil, method = "GET") : Endpoint
  import = {"gin" => "github.com/gin-gonic/gin", "chi" => "github.com/go-chi/chi/v5", "echo" => "github.com/labstack/echo/v4", "fiber" => "github.com/gofiber/fiber/v2", "mux" => "github.com/gorilla/mux", "web" => "gitea.dev/modules/web"}[framework]
  if gate.nil? && framework.in?("chi", "mux")
    gate = <<-GO
      func checkpoint(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
          if r.Header.Get("Authorization") == "" {
            http.Error(w, "unauthorized", 401)
            return
          }
          next.ServeHTTP(w, r)
        })
      }
      GO
  end
  gate ||= <<-GO
    func checkpoint(c *gin.Context) {
      if c.GetHeader("Authorization") == "" {
        c.AbortWithStatus(401)
      }
    }
    GO
  source = %(package main\nimport "#{import}"\nimport "net/http"\n#{gate}\n#{body})
  lines = source.lines
  row = lines.index!(&.includes?("// target")) + 1
  tech = framework == "web" ? "chi" : framework
  run_go_auth(lines, "/x", method, row, "go_#{tech}")
end

private def structural_scope_proofs(source : String, imports : Hash(String, String)) : Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::MiddlewareProof))
  result = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::MiddlewareProof)).new
  Noir::TreeSitter.parse_go(source) do |root|
    result = Noir::TreeSitterGoRouteExtractor.guard_middleware(root, source, imports)
  end
  result
end

describe "GoAuthTagger structural scope" do
  {
    "router Use"        => "r.Use(checkpoint)",
    "group Use"         => "g := r.Group(\"/\")\ng.Use(checkpoint)",
    "group constructor" => "g := r.Group(\"/\", checkpoint)",
    "ancestor Use"      => "r.Use(checkpoint)\ng := r.Group(\"/\")",
    "chained group"     => "g := r.Group(\"/\").Use(checkpoint)",
  }.each do |name, setup|
    it "follows Gin #{name} without replacing the retained tag" do
      receiver = setup.includes?("g :=") ? "g" : "r"
      endpoint = structural_scope_endpoint("func routes(r *gin.Engine) {\n#{setup}\n#{receiver}.GET(\"/x\", AuthRequired, h) // target\n}")
      endpoint.tags.map(&.description).should eq(["Protected by Go AuthRequired middleware"])
      endpoint.resolution.should be_nil
    end
  end

  {
    "Use after registration"     => "r.GET(\"/x\", AuthRequired, h) // target\nr.Use(checkpoint)",
    "a child created before Use" => "g := r.Group(\"/\")\nr.Use(checkpoint)\ng.GET(\"/x\", AuthRequired, h) // target",
    "conditional Use"            => "if cfg.Enabled {\nr.Use(checkpoint)\n}\nr.GET(\"/x\", AuthRequired, h) // target",
    "switch Use"                 => "switch cfg.Mode {\ncase 1: r.Use(checkpoint)\n}\nr.GET(\"/x\", AuthRequired, h) // target",
    "loop Use"                   => "for _, m := range cfg.Middleware {\nr.Use(checkpoint, m)\n}\nr.GET(\"/x\", AuthRequired, h) // target",
    "reassignment"               => "r.Use(checkpoint)\nr = gin.New()\nr.GET(\"/x\", AuthRequired, h) // target",
    "shadowing"                  => "r.Use(checkpoint)\n{\nr := gin.New()\nr.GET(\"/x\", AuthRequired, h) // target\n}",
    "conditional reassignment"   => "r.Use(checkpoint)\nif cfg.Enabled { r = gin.New() }\nr.GET(\"/x\", AuthRequired, h) // target",
    "captured reassignment"      => "r.Use(checkpoint)\nf := func() { r = gin.New() }; f()\nr.GET(\"/x\", AuthRequired, h) // target",
    "sibling group"              => "g := r.Group(\"/\", checkpoint)\nr.GET(\"/x\", AuthRequired, h) // target",
    "unknown middleware"         => "r.Use(AuthUnknown)\nr.GET(\"/x\", AuthRequired, h) // target",
    "registrar"                  => "g := r.Group(\"/\", checkpoint)\nregister(g)\n}\nfunc register(g *gin.RouterGroup) {\ng.GET(\"/x\", AuthRequired, h) // target",
  }.each do |name, statements|
    it "keeps Gin #{name} matched" do
      endpoint = structural_scope_endpoint("func routes(r *gin.Engine) {\n#{statements}\n}")
      endpoint.tags.map(&.name).should eq(["auth"])
      endpoint.resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "recognizes constructors and aliased imports but vetoes import shadowing" do
    source = "package main\nfunc routes() {\nr := engine.New()\nr.Use(checkpoint)\nr.GET(\"/x\", h)\n}"
    imports = {"engine" => "github.com/gin-gonic/gin"}
    structural_scope_proofs(source, imports)[4].map(&.arg).should eq(["checkpoint"])
    structural_scope_proofs(source.sub("r := engine.New()", "engine := factory\nr := engine.New()"), imports).should be_empty
  end

  it "keeps instances and reused names in different functions separate" do
    source = "package main\nfunc one(r *gin.Engine) {\nr.Use(checkpoint)\nr.GET(\"/x\", h)\n}\nfunc two(r *gin.Engine) {\nr.GET(\"/x\", h)\n}"
    proofs = structural_scope_proofs(source, {"gin" => "github.com/gin-gonic/gin"})
    proofs[3].map(&.arg).should eq(["checkpoint"])
    proofs[6].should be_empty
  end

  it "follows Echo instance Use after registration, but snapshots group Use" do
    positive = "func routes(e *echo.Echo) {\ne.GET(\"/x\", h, AuthRequired, logging) // target\ne.Use(checkpoint)\n}"
    structural_scope_endpoint(positive, "echo").resolution.should be_nil
    before = "func routes(e *echo.Echo) {\ng := e.Group(\"/\")\ng.Use(checkpoint)\ng.GET(\"/x\", h, AuthRequired, logging) // target\n}"
    structural_scope_endpoint(before, "echo").resolution.should be_nil
    after = before.sub("g.Use(checkpoint)\n", "").sub(" // target", " // target\ng.Use(checkpoint)")
    structural_scope_endpoint(after, "echo").resolution.should eq({"guard" => "heuristic"})
  end

  it "follows Echo middleware after its handler using the tree's arguments" do
    endpoint = structural_scope_endpoint("func routes(e *echo.Echo) {\ne.GET(\"/x\", h, AuthRequired, checkpoint) // target\n}", "echo")
    endpoint.tags.any?(&.name.==("auth")).should be_true
    endpoint.resolution.should be_nil
    handler = structural_scope_endpoint("func routes(e *echo.Echo) {\ne.GET(\"/x\", checkpoint, AuthRequired) // target\n}", "echo")
    handler.resolution.should eq({"guard" => "heuristic"})
  end

  %w[Group Route].each do |method|
    it "follows chi #{method} callback Use without claiming the sibling" do
      prefix = method == "Route" ? "\"/\", " : ""
      body = "func routes(r chi.Router) {\nr.Use(AuthUnknown)\nr.#{method}(#{prefix}func(r chi.Router) {\nr.Use(checkpoint)\nr.Get(\"/x\", h) // target\n})\n}"
      structural_scope_endpoint(body, "chi").resolution.should be_nil
      sibling = body.sub(" // target", "").sub("})", "})\nr.Get(\"/x\", h) // target")
      structural_scope_endpoint(sibling, "chi").resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "follows a chi With value and leaves a conditional install matched" do
    body = "func routes(r chi.Router) {\nr.Use(AuthUnknown)\ng := r.With(checkpoint)\ng.Get(\"/x\", h) // target\n}"
    structural_scope_endpoint(body, "chi").resolution.should be_nil
    conditional = "func routes(r chi.Router) {\nr.Use(AuthUnknown)\nif cfg.Enabled { r.Use(checkpoint) }\nr.Get(\"/x\", h) // target\n}"
    structural_scope_endpoint(conditional, "chi").resolution.should eq({"guard" => "heuristic"})
  end

  it "follows mux Use after a subrouter's registration" do
    body = "func routes(r *mux.Router) {\ng := r.PathPrefix(\"/\").Subrouter()\nr.Use(AuthUnknown)\ng.HandleFunc(\"/x\", h).Methods(\"GET\") // target\nr.Use(checkpoint)\n}"
    endpoint = structural_scope_endpoint(body, "mux")
    # The existing scope tracker may not tag a late Use. Seed the matched
    # status separately below to exercise the independent extractor proof.
    source = "package main\n#{body}"
    proofs = structural_scope_proofs(source, {"mux" => "github.com/gorilla/mux"})
    proofs[4].map(&.arg).should eq(["AuthUnknown", "checkpoint"])
    endpoint.tags.any?(&.name.==("auth")).should be_true
    endpoint.resolution.should be_nil
  end

  it "does not certify Echo/mux installation after a possible early return" do
    %w[echo mux].each do |kind|
      source = "package main\nfunc routes(r *#{kind}.#{kind == "echo" ? "Echo" : "Router"}) {\nr.GET(\"/x\", h)\nif flag { return }\nr.Use(checkpoint)\n}"
      import = kind == "echo" ? "github.com/labstack/echo/v4" : "github.com/gorilla/mux"
      structural_scope_proofs(source, {kind => import})[2].should be_empty
    end
  end

  it "follows only Fiber's unprefixed one-handler Use before the route" do
    body = "func routes(r *fiber.App) {\nr.Use(checkpoint)\nr.Get(\"/x\", AuthRequired, h) // target\n}"
    structural_scope_endpoint(body, "fiber").resolution.should be_nil
    [body.sub("r.Use(checkpoint)", "r.Use(\"/admin\", checkpoint)"),
     body.sub("r.Use(checkpoint)\n", "").sub(" // target", " // target\nr.Use(checkpoint)")].each do |negative|
      structural_scope_endpoint(negative, "fiber").resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "follows Gitea's synchronous Group arguments without leaking to siblings or other routers" do
    body = "func routes(r *web.Router, other *web.Router) {\nr.AfterRouting(contextSetup)\nr.Group(\"/\", func() {\nr.Get(\"/x\", AuthRequired, h) // target\n}, checkpoint)\n}"
    structural_scope_endpoint(body, "web").resolution.should be_nil
    [body.sub("r.Get(", "other.Get("),
     body.sub(" // target", "").sub("}, checkpoint)", "}, checkpoint)\nr.Get(\"/x\", AuthRequired, h) // target")].each do |negative|
      endpoint = structural_scope_endpoint(negative, "web")
      endpoint.tags.any?(&.name.==("auth")).should be_true
      endpoint.resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "keeps skippers, unread flags and request-specific exemptions matched" do
    body = "func routes(r *gin.Engine) {\nr.Use(checkpoint(false))\nr.GET(\"/x\", AuthRequired, h) // target\n}"
    [body.sub("checkpoint(false)", "checkpoint(Config{Skipper: custom})"),
     body.sub("checkpoint(false)", "checkpoint(cfg.Required)")].each do |negative|
      gate = "func checkpoint(required bool) gin.HandlerFunc {\nreturn func(c *gin.Context) {\nif required {\nif c.GetHeader(\"Authorization\") == \"\" {\nc.AbortWithStatus(401)\n}\n}\n}\n}"
      endpoint = structural_scope_endpoint(negative, "gin", gate)
      endpoint.tags.any?(&.name.==("auth")).should be_true
      endpoint.resolution.should eq({"guard" => "heuristic"})
    end
    gate = <<-GO
      func checkpoint(next http.Handler) http.Handler {
        return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
          if r.URL.Path == "/x" || r.Method == http.MethodOptions {
            next.ServeHTTP(w, r)
            return
          }
          if r.Header.Get("Authorization") == "" {
            http.Error(w, "unauthorized", 401)
            return
          }
          next.ServeHTTP(w, r)
        })
      }
      GO
    %w[GET OPTIONS].each do |method|
      source = "func routes(r chi.Router) {\nr.Use(AuthUnknown)\nr.Use(checkpoint)\nr.Get(\"/x\", h) // target\n}"
      structural_scope_endpoint(source, "chi", gate, method).resolution.should eq({"guard" => "heuristic"})
    end
  end
  it "vetoes router field writes, indirect replacement and goto installs" do
    ["r.Handlers = nil", "*r = *gin.New()", "if !cfg.Auth { goto route }; r.Use(checkpoint); route:"].each do |mutation|
      body = "func routes(r *gin.Engine) {\nr.Use(checkpoint)\n#{mutation}\nr.GET(\"/x\", AuthRequired, h) // target\n}"
      structural_scope_endpoint(body).resolution.should eq({"guard" => "heuristic"})
    end
  end

  it "does not leak a block local into an outer package router" do
    body = "var r = gin.New()\nfunc routes() {\n{ r := gin.New(); r.Use(checkpoint) }\nr.GET(\"/x\", AuthRequired, h) // target\n}"
    structural_scope_endpoint(body).resolution.should eq({"guard" => "heuristic"})
  end

  it "vetoes ambiguous rows even when the other receiver is unresolved" do
    body = "func routes(r *gin.Engine) {\ns := makeRouter()\nr.Use(checkpoint)\nr.GET(\"/private\", h); s.GET(\"/x\", AuthRequired, h) // target\n}"
    structural_scope_endpoint(body).resolution.should eq({"guard" => "heuristic"})
  end

  it "keeps unread global flags, imported exemptions and permission arguments matched" do
    ["tokenRequired && c.GetHeader(\"Authorization\") == \"\"", "features.TokenRequired && c.GetHeader(\"Authorization\") == \"\"", "cfg.Required && c.GetHeader(\"Authorization\") == \"\"", "features.Enabled && c.GetHeader(\"Authorization\") == \"\""].each do |condition|
      gate = "func checkpoint() gin.HandlerFunc {\nreturn func(c *gin.Context) {\nif #{condition} {\nc.AbortWithStatus(401)\n}\n}\n}"
      body = "func routes(r *gin.Engine) {\nr.Use(checkpoint())\nr.GET(\"/x\", AuthRequired, h) // target\n}"
      structural_scope_endpoint(body, "gin", gate).resolution.should eq({"guard" => "heuristic"})
    end
    gate = "func checkpoint(c *gin.Context) {\nif allowlist.IsPublic(c.Request) {\nc.Next()\nreturn\n}\nif c.GetHeader(\"Authorization\") == \"\" {\nc.AbortWithStatus(401)\n}\n}"
    body = "func routes(r *gin.Engine) {\nr.Use(checkpoint)\nr.GET(\"/x\", AuthRequired, h) // target\n}"
    structural_scope_endpoint(body, "gin", gate).resolution.should eq({"guard" => "heuristic"})
    gate = "func checkpoint(accessMode perm.AccessMode) func(ctx *context.APIContext) {\nreturn func(ctx *context.APIContext) {\nif ctx.Package.AccessMode < accessMode {\nctx.Error(403)\n}\n}\n}"
    body = "func routes(r *web.Router) {\nr.Group(\"/\", func() {\nr.Get(\"/x\", AuthRequired, h) // target\n}, checkpoint(perm.AccessModeRead))\n}"
    structural_scope_endpoint(body, "web", gate).resolution.should eq({"guard" => "heuristic"})
  end
  it "follows a zero-argument factory without treating its empty parameter list as a waiver" do
    gate = "func checkpoint() func(ctx *Context) {\nreturn func(ctx *Context) {\nif ctx.IsSigned {\nreturn\n}\nctx.Error(401)\n}\n}"
    body = "func routes(r *gin.Engine) {\nr.Use(checkpoint())\nr.GET(\"/x\", AuthRequired, h) // target\n}"
    structural_scope_endpoint(body, "gin", gate).resolution.should be_nil
  end

  ["reset(&r)", "reset(r)", "alias := r; alias.Handlers = nil", "var alias = r; alias.Handlers = nil", "alias := any(r).(*gin.Engine); alias.Handlers = nil", "alias := r.GET(\"/alias\", h); reset(alias)", "alias := r.Use(other); alias.Handlers = nil"].each do |mutation|
    it "keeps the escape #{mutation} matched" do
      body = "func routes(r *gin.Engine) {\nr.Use(checkpoint)\n#{mutation}\nr.GET(\"/x\", AuthRequired, h) // target\n}"
      structural_scope_endpoint(body).resolution.should eq({"guard" => "heuristic"})
    end
  end
  it "does not follow a definition selected by receiver type or a caller-independent refusal" do
    method = "func (mw *Middleware) checkpoint(c *gin.Context) {\nif c.GetHeader(\"Authorization\") == \"\" {\nc.AbortWithStatus(401)\n}\n}"
    body = "func routes(r *gin.Engine, mw *Middleware) {\nr.Use(mw.checkpoint)\nr.GET(\"/x\", AuthRequired, h) // target\n}"
    structural_scope_endpoint(body, "gin", method).resolution.should eq({"guard" => "heuristic"})
    plain = "func checkpoint(c *gin.Context) {\nc.AbortWithStatus(401)\n}"
    structural_scope_endpoint(body.sub("mw.checkpoint", "checkpoint"), "gin", plain).resolution.should eq({"guard" => "heuristic"})
  end
end
