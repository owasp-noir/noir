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
end
