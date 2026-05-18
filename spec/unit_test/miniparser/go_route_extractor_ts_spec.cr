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
end
