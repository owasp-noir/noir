require "spec"
require "../../../src/miniparsers/kotlin_ktor_route_extractor_ts"

describe Noir::TreeSitterKotlinKtorRouteExtractor do
  it "emits routes from a flat routing block" do
    source = <<-KT
      routing {
          get("/") { call.respondText("hi") }
          post("/users") { call.respondText("ok") }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/"},
      {"POST", "/users"},
    ])
  end

  it "composes route() prefixes onto nested verbs" do
    source = <<-KT
      routing {
          route("/api") {
              get("/status") { }
              route("/v1") {
                  get("/health") { }
                  post("/submit") { }
              }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/status"},
      {"GET", "/api/v1/health"},
      {"POST", "/api/v1/submit"},
    ])
  end

  it "treats authenticate{} as a passthrough wrapper" do
    source = <<-KT
      routing {
          authenticate("auth-jwt") {
              get("/profile") { }
              route("/admin") {
                  get("/dashboard") { }
              }
          }
          get("/health") { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/profile"},
      {"GET", "/admin/dashboard"},
      {"GET", "/health"},
    ])
  end

  it "supports all standard verbs" do
    source = <<-KT
      routing {
          get("/a") { }
          post("/b") { }
          put("/c") { }
          delete("/d") { }
          patch("/e") { }
          head("/f") { }
          options("/g") { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map(&.verb).should eq(["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS"])
  end

  describe "handler-body parameter scan" do
    it "captures call.receive<T>() as the receive_type" do
      source = <<-KT
        routing {
            post("/users") {
                val user = call.receive<User>()
                call.respondText("ok")
            }
        }
        KT

      route = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source).first
      route.receive_type.should eq("User")
    end

    it "captures call.parameters[\"name\"] entries" do
      source = <<-KT
        routing {
            get("/items/{id}") {
                val id = call.parameters["id"]
                val category = call.parameters["category"]
            }
        }
        KT

      route = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source).first
      route.query_params.should eq(["id", "category"])
    end

    it "captures call.request.headers[\"name\"] entries" do
      source = <<-KT
        routing {
            put("/x") {
                val key = call.request.headers["X-API-Key"]
                val auth = call.request.headers["Authorization"]
            }
        }
        KT

      route = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source).first
      route.header_params.should eq(["X-API-Key", "Authorization"])
    end

    it "ignores params on sibling routes" do
      source = <<-KT
        routing {
            get("/a") {
                val id = call.parameters["a"]
            }
            get("/b") {
                val id = call.parameters["b"]
            }
        }
        KT

      routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
      routes[0].query_params.should eq(["a"])
      routes[1].query_params.should eq(["b"])
    end
  end

  it "skips verb DSL calls without a string-literal path" do
    # `get { ... }` (resource-based routing) currently isn't
    # supported. We just ignore it rather than emitting an empty
    # path.
    source = <<-KT
      routing {
          get { call.respondText("ok") }
          get("/real") { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/real"])
  end

  it "tracks the source line of the verb call" do
    source = <<-KT
      routing {
          get("/a") { }
          get("/b") { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    (routes[1].line - routes[0].line).should eq(1)
  end
end
