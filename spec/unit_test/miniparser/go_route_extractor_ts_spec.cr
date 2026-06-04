require "spec"
require "../../../src/miniparsers/go_route_extractor_ts"

describe Noir::TreeSitterGoRouteExtractor do
  it "extracts every verb route in the Gin fixture with resolved group prefixes" do
    path = File.expand_path("../../../functional_test/fixtures/go/gin/server.go", __FILE__)
    source = File.read(path)

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)

    triples = routes.map { |r| {r.verb, r.path} }.sort!
    # Covers: direct verb calls on `r`, nested group chains
    # (users := r.Group("/group") → v1 := users.Group("/v1")),
    # and the `authorized := r.Group("/")` + path-without-slash case.
    triples.should eq([
      {"DELETE", "/mixed-delete"},
      {"GET", "/admin"},
      {"GET", "/group/users"},
      {"GET", "/group/v1/migration"},
      {"GET", "/mixed-get"},
      {"GET", "/multiline"},
      {"GET", "/ping"},
      {"POST", "/admin"},
      {"POST", "/mixed-post"},
      {"POST", "/submit"},
      {"PUT", "/mixed-put"},
    ].sort)
  end

  it "handles multi-line verb calls that the legacy line-oriented extractor misses" do
    source = <<-GO
      package main
      func main() {
          r := gin.Default()
          r.GET(
              "/multi",
              handler,
          )
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/multi"}])
  end

  it "stacks nested groups correctly" do
    source = <<-GO
      package main
      func main() {
          r := chi.NewRouter()
          api := r.Group("/api")
          v1 := api.Group("/v1")
          users := v1.Group("/users")
          users.GET("/me", h)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/api/v1/users/me"])
  end

  it "leaves unknown router variables untouched (no group prefix guess)" do
    source = <<-GO
      package main
      func main() {
          unknown.GET("/bare", h)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.router_name, r.verb, r.path} }.should eq([{"unknown", "GET", "/bare"}])
  end

  it "ignores string literals that happen to look like paths in non-verb calls" do
    source = <<-GO
      package main
      func main() {
          c.Cookie("abcd_token")
          r.Something("/not-a-route", h)
          r.GET("/real", h)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/real"])
  end

  it "rejects net/http client calls that share the GET/POST method names" do
    # Regression: `http.Get("http://localhost:8080/")` from
    # gin-gonic/examples/otel emitted a bogus `/http://localhost:8080/`
    # route. Real router paths are relative and never carry a scheme,
    # so reject absolute URLs to keep the net/http client API out.
    source = <<-GO
      package main
      func main() {
          r := gin.Default()
          r.GET("/legit", handler)
          http.Get("http://localhost:8080/")
          http.Post("https://example.com/api", "application/json", nil)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/legit"])
  end

  it "rejects single-arg verb calls like gin.Context.Get value lookups" do
    # Regression: `c.Get("clientChan")` from
    # gin-gonic/examples/server-sent-event emitted a bogus `/clientChan`
    # route. Real route registrations always pass a handler argument
    # after the path; value-lookup helpers take a single string.
    source = <<-GO
      package main
      func handler(c *gin.Context) {
          v, ok := c.Get("clientChan")
          _ = v
          _ = ok
      }
      func main() {
          r := gin.Default()
          r.GET("/legit", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/legit"])
  end

  it "resolves string constants and concatenations used as paths" do
    source = <<-GO
      package main
      const api = "/api"
      const users = "/users"

      func main() {
          r := gin.Default()
          group := r.Group(api)
          group.GET(users + "/:id", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/api/users/:id"}])
  end

  it "extracts routes registered on inline group chains" do
    source = <<-GO
      package main

      func main() {
          r := gin.Default()
          r.Group("/api").GET("/users", handler)
          r.Group("/api").Group("/v1").POST("/teams", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/users"},
      {"POST", "/api/v1/teams"},
    ])
  end

  it "detects root engine/router names from constructors and engine-typed params" do
    source = <<-GO
      package main

      func boot() {
          r := gin.New()
          e := echo.New()
          mux := chi.NewRouter()
          v1 := r.Group("/api/v1")
          v1.GET("/users", h)
      }

      func register(app *gin.Engine, grp *gin.RouterGroup) {
          grp.GET("/posts", h)
      }
      GO

    names = Noir::TreeSitterGoRouteExtractor.extract_engine_names(source)
    # Constructors (r/e/mux) and the *gin.Engine param (app) are roots;
    # `grp` is a *gin.RouterGroup (a real group param) and `v1` is a
    # derived group — neither is an engine.
    names.includes?("r").should be_true
    names.includes?("e").should be_true
    names.includes?("mux").should be_true
    names.includes?("app").should be_true
    names.includes?("grp").should be_false
    names.includes?("v1").should be_false
  end

  it "peels .Use(...) middleware chains before the verb call" do
    # Gin's `RouterGroup.Use(...)` / `Engine.Use(...)` return the
    # receiver, so `r.Use(mw).GET(...)` and
    # `r.Group("/x").Use(mw).POST(...)` are valid. The verb's operand is
    # the `.Use(...)` call; without peeling it the routes were dropped.
    source = <<-GO
      package main
      func main() {
          g := gin.New()
          g.Use(logMW).GET("/ping", pong)
          g.Group("/user").Use(authMW).POST("/", createUser)
          g.Group("/").Use(reqMW).POST("/message", createMsg)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/ping"},
      {"POST", "/message"},
      {"POST", "/user/"},
    ].sort)
  end

  it "collects group declarations whose RHS ends in a .Use(...) chain" do
    # `v1 := r.Group("/v1").Use(mw)` — the `.Use(...)` wraps the real
    # `.Group(...)` call. The group name must still bind to `/v1` so the
    # verb routes registered on `v1` later resolve with the prefix.
    source = <<-GO
      package main
      func main() {
          r := gin.Default()
          v1 := r.Group("/v1").Use(authMW)
          v1.GET("/users", listUsers)
          v2 := r.Group("/v2").Use(a).Use(b)
          v2.POST("/items", addItem)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/v1/users"},
      {"POST", "/v2/items"},
    ].sort)
  end

  it "collects group assignments from var declarations and later assignments" do
    source = <<-GO
      package main

      func main() {
          r := gin.Default()
          var api = r.Group("/api")
          var v1 *gin.RouterGroup
          v1 = api.Group("/v1")
          v1.GET("/users", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/api/v1/users"}])
  end

  it "does not loop on reassigned string identifiers" do
    source = <<-GO
      package main

      func main() {
          r := gin.Default()
          path := "/first"
          path = "/second"
          r.GET(path, handler)
          r.GET("/legit", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/legit"}])
  end

  it "extracts gorilla mux Handle routes and named tail chains" do
    source = <<-GO
      package main
      func main() {
          r := mux.NewRouter()
          r.Handle("/handler", http.HandlerFunc(handler)).Methods("POST").Name("handler.create")
          r.HandleFunc("/multi", handler).Methods("GET", "POST").Name("multi")
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source, handlefunc_methods: true)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/multi"},
      {"POST", "/handler"},
      {"POST", "/multi"},
    ].sort)
  end

  it "extracts gorilla mux route builder chains" do
    source = <<-GO
      package main
      func main() {
          r := mux.NewRouter()
          r.Methods("GET").Path("/builder").HandlerFunc(handler)
          r.Path("/alternate").Methods("PATCH").Handler(http.HandlerFunc(handler))
          r.Methods("GET").Path("/filtered").Queries("type", "{type}", "page", "{page}").HandlerFunc(handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source, handlefunc_methods: true)
    routes.map { |r| {r.verb, r.path, r.query_params} }.sort_by! { |r| r[1] }.should eq([
      {"PATCH", "/alternate", [] of String},
      {"GET", "/builder", [] of String},
      {"GET", "/filtered", ["type", "page"]},
    ])
  end

  it "preserves wildcard methods for unconstrained gorilla mux routes" do
    source = <<-GO
      package main
      func main() {
          r := mux.NewRouter()
          r.HandleFunc("/all", handler)
          r.Path("/all-builder").HandlerFunc(handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source, handlefunc_methods: true)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"ANY", "/all"},
      {"ANY", "/all-builder"},
    ].sort)
  end

  it "does not mint phantom routes from verb-named value helpers" do
    # A cache's `Put`/`Get` and similar value helpers share a verb name
    # but take a context/receiver as their first argument, not a URL.
    # The path must be the FIRST positional argument of a verb call, so
    # these must produce no routes.
    source = <<-GO
      package main
      func main() {
          c.Put(context.Background(), "hello", "world", time.Minute)
          bm.Get(ctx, "name")
          store.Delete(ctx, "key")
          r.GET("/real", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/real"}])
  end

  it "extracts beego controller routes with explicit method mappings" do
    source = <<-GO
      package main
      func main() {
          web.Router("/health", ctrl, "get:Health")
          web.Router("/update", ctrl, "post:Update")
          web.Router("/getOrPost", ctrl, "get,post:GetOrPost")
          web.Router("/multi", ctrl, "get:Read;delete:Remove")
          web.Router("/any", ctrl, "*:Any")
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_beego_routes(source)
    routes.map { |r| {r.verb, r.path, r.handler} }.sort!.should eq([
      {"ANY", "/any", "Any"},
      {"DELETE", "/multi", "Remove"},
      {"GET", "/getOrPost", "GetOrPost"},
      {"GET", "/health", "Health"},
      {"GET", "/multi", "Read"},
      {"POST", "/getOrPost", "GetOrPost"},
      {"POST", "/update", "Update"},
    ].sort)
  end

  it "resolves mapping-less beego controller routes from implemented methods" do
    source = <<-GO
      package main
      func main() {
          ctrl := &MainController{}
          web.Router("/", ctrl)
          web.Router("/inline", &OtherController{})
      }
      func (c *MainController) Get()  {}
      func (c *MainController) Post() {}
      func (c *MainController) Helper() {}
      func (c *OtherController) Delete() {}
      GO

    methods = Noir::TreeSitterGoRouteExtractor.extract_controller_methods(source)
    methods["MainController"].sort.should eq(["Get", "Post"])
    methods["OtherController"].should eq(["Delete"])

    routes = Noir::TreeSitterGoRouteExtractor.extract_beego_routes(source, methods)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"DELETE", "/inline"},
      {"GET", "/"},
      {"POST", "/"},
    ].sort)
  end

  it "falls back to GET for beego controllers it can't resolve" do
    source = <<-GO
      package main
      func main() {
          web.Router("/external", &controllers.UserController{})
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_beego_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/external"}])
  end

  it "does not fan out a cross-package controller using a same-named local type" do
    # A qualified `&controllers.UserController{}` is cross-package; even
    # though THIS package defines a `UserController` with Get+Post, the
    # qualified route must take the unresolved fallback (single GET), not
    # borrow the local type's methods.
    source = <<-GO
      package main
      func main() {
          web.Router("/local", &UserController{})
          web.Router("/external", &controllers.UserController{})
      }
      func (c *UserController) Get()  {}
      func (c *UserController) Post() {}
      GO

    methods = Noir::TreeSitterGoRouteExtractor.extract_controller_methods(source)
    routes = Noir::TreeSitterGoRouteExtractor.extract_beego_routes(source, methods)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/external"},
      {"GET", "/local"},
      {"POST", "/local"},
    ].sort)
  end

  it "ignores Router calls on non-beego operands" do
    source = <<-GO
      package main
      func main() {
          db.Router("/not-a-route", handler)
          web.Router("/yes", &C{})
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_beego_routes(source)
    routes.map(&.path).should eq(["/yes"])
  end

  it "drops gf value-getter `.Get(...)` and BindMiddleware/BindHookHandler" do
    # genv.Get / r.Get / gmeta.Get pass a bare key, never a `/`-path;
    # BindMiddleware/BindHookHandler attach to a pattern but aren't routes.
    source = <<-GO
      package main
      func main() {
          _ = genv.Get("GOPATH").String()
          _ = r.Get("authorization").String()
          _ = gmeta.Get(Req{}, "path").String()
          s.BindMiddleware("/*any", mw)
          s.BindHookHandler("/*any", hook, mw)
          s.BindHandler("/real", handler)
          s.GET("/verb", handler)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_gf_routes(source)
    routes.map(&.path).sort!.should eq(["/real", "/verb"])
  end

  it "extracts gf g.Meta standardized routes with method fan-out and params" do
    source = <<-GO
      package v1
      type GetUserReq struct {
          g.Meta `path:"/user/get" method:"get"`
          Id     int    `json:"id"`
      }
      type SaveReq struct {
          g.Meta `path:"/user/save" method:"put,patch"`
      }
      type ListReq struct {
          g.Meta `path:"/user/list"`
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_gf_meta_routes(source)
    pairs = routes.flat_map { |r| r.methods.map { |m| {m, r.path} } }.sort!
    pairs.should eq([
      # method-less -> "ALL" (analyzer fans this out to every verb)
      {"ALL", "/user/list"},
      {"GET", "/user/get"},
      {"PATCH", "/user/save"},
      {"PUT", "/user/save"},
    ].sort)
    routes.find! { |r| r.path == "/user/get" }.params.should eq(["id"])
  end

  it "extracts go-zero AddRoutes slice, AddRoute single, and group prefixes" do
    source = <<-GO
      package handler
      func RegisterHandlers(server *rest.Server) {
          server.AddRoutes(
              []rest.Route{
                  {Method: http.MethodPost, Path: "/user/login", Handler: h},
                  {Method: http.MethodGet, Path: "/user/info", Handler: h},
              },
              rest.WithPrefix("/v1"),
          )
          server.AddRoute(rest.Route{Method: http.MethodGet, Path: "/"})
          g := server.Group("/api/v1")
          g.AddRoute(rest.Route{Method: http.MethodDelete, Path: "/items/:id"})
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_gozero_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"DELETE", "/api/v1/items/:id"},
      {"GET", "/"},
      {"GET", "/v1/user/info"},
      {"POST", "/v1/user/login"},
    ].sort)
  end

  it "applies iris closure-group prefixes and method-first Handle/HandleMany" do
    source = <<-GO
      package main
      func main() {
          app := iris.New()
          app.Handle("GET", "/h", handler)
          app.HandleMany("GET POST", "/many", handler)
          app.PartyFunc("/pf", func(p iris.Party) {
              p.Get("/inside", handler)
              p.PartyFunc("/admin", func(a iris.Party) {
                  a.Get("/stats", handler)
              })
          })
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
      source, group_method: "Party",
      handle_method: "Handle", handle_many_method: "HandleMany",
      closure_group_methods: ["Party", "PartyFunc"]
    )
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"GET", "/h"},
      {"GET", "/many"},
      {"GET", "/pf/admin/stats"},
      {"GET", "/pf/inside"},
      {"POST", "/many"},
    ].sort)
  end

  it "does not treat zap.Any logging field constructors as routes" do
    source = <<-GO
      package main
      func main() {
          r := gin.Default()
          r.GET("/ok", handler)
          global.GVA_LOG.Info("msg", zap.Any("error", err))
          slog.Any("mode", val)
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/ok"}])
  end

  it "decodes chi MethodFunc/HandleFunc/Handle net-http registrations" do
    source = <<-GO
      package main
      func main() {
          r := chi.NewRouter()
          r.Route("/api", func(r chi.Router) {
              r.MethodFunc("GET", "/health", health)
              r.HandleFunc("/everything", everything)
          })
          r.Handle("/metrics", promhttp.Handler())
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
    routes.map { |r| {r.verb, r.path} }.sort!.should eq([
      {"ANY", "/api/everything"},
      {"ANY", "/metrics"},
      {"GET", "/api/health"},
    ].sort)
  end

  it "does not read stdlib net/http Handle/HandleFunc as chi routes" do
    source = <<-GO
      package main
      func main() {
          r := chi.NewRouter()
          r.Get("/", index)
          http.HandleFunc("/legacy", legacy)
          http.Handle("/metrics", promhttp.Handler())
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/"}])
  end

  it "skips only the receiver-matched mounted method body, not a same-named method" do
    # `subResource.Routes()` is the mount target; `server.Routes()` is a
    # top-level builder used directly and must keep its routes.
    source = <<-GO
      package main
      func (s server) Routes() chi.Router {
          r := chi.NewRouter()
          r.Get("/health", s.Health)
          return r
      }
      func (s subResource) Routes() chi.Router {
          r := chi.NewRouter()
          r.Get("/item", s.Item)
          return r
      }
      GO

    routes = Noir::TreeSitterGoRouteExtractor.extract_chi_routes(source, Set{"subResource.Routes"})
    routes.map { |r| {r.verb, r.path} }.should eq([{"GET", "/health"}])
  end
end
