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

  it "extracts routes from Route extension functions" do
    source = <<-KT
      import io.ktor.server.routing.Route

      fun Route.customerRoutes() {
          route("/customer") {
              get { }
              post("/{id}") { }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/customer"},
      {"POST", "/customer/{id}"},
    ])
  end

  it "extracts routes from modified Route extension functions" do
    source = <<-KT
      import io.ktor.server.routing.Route

      private fun Route.adminRoutes() {
          get("/admin") { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/admin"},
    ])
  end

  it "extracts route(path, method) handlers" do
    source = <<-KT
      routing {
          route("/hello", HttpMethod.Get) {
              handle { call.respondText("ok") }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/hello"},
    ])
  end

  it "resolves constant and templated route paths" do
    source = <<-KT
      package com.example

      object Paths {
          const val API = "/api"
      }

      const val USERS = "/users"

      routing {
          route(Paths.API + "/v1") {
              get(USERS) { }
              get("/tenants/$tenantId/items") { }
          }
      }
      KT

    constants = Noir::TreeSitterKotlinKtorRouteExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source, constants)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/v1/users"},
      {"GET", "/api/v1/tenants/{tenantId}/items"},
    ])
  end

  it "does not resolve route paths from project-wide bare constants" do
    source = <<-KT
      routing {
          get(USERS) { }
          route(API) {
              get("/nested") { }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source, {
      "USERS" => "/wrong-users",
      "API"   => "/wrong-api",
    })
    routes.should be_empty
  end

  it "does not drop qualifiers when resolving route constants" do
    source = <<-KT
      routing {
          get(Other.API) { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source, {
      "API" => "/wrong",
    })
    routes.should be_empty
  end

  it "treats install(RoutingRoot) as a routing entry point" do
    source = <<-KT
      fun Application.module() {
          install(RoutingRoot) {
              get("/installed") { }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/installed"},
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

    it "captures common query, header, body, and form access variants" do
      source = <<-KT
        routing {
            post("/profile") {
                val query = call.request.queryParameters["preview"]
                val page = call.request.queryParameters.get("page")
                val id = call.parameters.get("id")
                val apiKey = call.request.headers.get("X-API-Key")
                val auth = call.request.header("Authorization")
                val form = call.receiveParameters()
                val email = form["email"]
                val phone = form.get("phone")
                val body = call.receiveText()
            }
        }
        KT

      route = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source).first
      route.has_body?.should be_true
      route.query_params.should eq(["preview", "page", "id"])
      route.header_params.should eq(["X-API-Key", "Authorization"])
      route.form_params.should eq(["email", "phone"])
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

  it "uses the current route prefix for verb DSL calls without a path argument" do
    source = <<-KT
      routing {
          route("/items") {
              get { call.respondText("ok") }
          }
          get("/real") { }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/items"},
      {"GET", "/real"},
    ])
  end

  it "does not treat unrelated get calls as routes outside routing contexts" do
    source = <<-KT
      fun helper(client: HttpClient) {
          client.get("/external")
          get("/local-helper")
      }

      routing {
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

  it "emits WebSocket and SSE handlers as GET routes" do
    source = <<-KT
      routing {
          webSocket("/echo") { }
          sse("/events") { }
          route("/v1") {
              webSocket("/feed") { }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/echo"},
      {"GET", "/events"},
      {"GET", "/v1/feed"},
    ])
  end

  it "does not mistake a plugin config DSL lambda for an HTTP verb route" do
    source = <<-KT
      routing {
          install(CachingHeaders) {
              options { call, content -> null }
          }
          route("/index") {
              get { call.respondText("Index") }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    # The `options { }` inside install(CachingHeaders) is config, not an
    # OPTIONS route; only the real GET /index should surface.
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/index"},
    ])
  end

  it "surfaces staticResources / staticFiles mounts as GET routes" do
    source = <<-KT
      routing {
          staticResources("/assets", "files")
          staticFiles("/r", File("uploads"))
          route("/v1") {
              staticResources("/static", "web") { }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/assets"},
      {"GET", "/r"},
      {"GET", "/v1/static"},
    ])
  end

  describe "type-safe resource routing" do
    it "resolves @Resource routes, composing nested + parent paths" do
      source = <<-KT
        @Resource("/articles")
        class Articles {
            @Resource("new")
            class New(val parent: Articles)
            @Resource("{id}")
            class Id(val parent: Articles, val id: Long) {
                @Resource("edit")
                class Edit(val parent: Id)
            }
        }

        fun Application.module() {
            routing {
                get<Articles> { }
                get<Articles.New> { }
                post<Articles> { }
                get<Articles.Id> { }
                get<Articles.Id.Edit> { }
            }
        }
        KT

      resources = Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(source)
      paths = Noir::TreeSitterKotlinKtorRouteExtractor.compose_resource_paths(resources)
      routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source, resource_paths: paths)
      routes.map { |r| {r.verb, r.path} }.should eq([
        {"GET", "/articles"},
        {"GET", "/articles/new"},
        {"POST", "/articles"},
        {"GET", "/articles/{id}"},
        {"GET", "/articles/{id}/edit"},
      ])
    end

    it "composes a constructor-property parent resource declared elsewhere" do
      api_module = <<-KT
        @Resource("/api")
        data object Root
        KT
      routes_module = <<-KT
        @Resource("/tags")
        class TagsResource(val root: Root = Root)

        fun Route.tagRoutes() {
            get<TagsResource> { }
        }
        KT

      resources = Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(api_module) +
                  Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(routes_module)
      paths = Noir::TreeSitterKotlinKtorRouteExtractor.compose_resource_paths(resources)
      routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(routes_module, resource_paths: paths)
      routes.map { |r| {r.verb, r.path} }.should eq([
        {"GET", "/api/tags"},
      ])
    end

    it "skips an unresolved type-safe route instead of emitting the bare prefix" do
      source = <<-KT
        fun Application.module() {
            routing {
                get<UnknownResource> { }
            }
        }
        KT

      Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source).should be_empty
    end

    it "treats a typed verb WITH a string path as a normal body route, not a resource" do
      # `post<EmailRequest>("/push/email") { }` (kopapi typed-body DSL):
      # the `<Type>` names the request body, the string is the real path.
      # Must NOT be mistaken for resource routing and dropped.
      source = <<-KT
        fun Route.notificationRoutes() {
            post<EmailRequest>("/push/email") { request -> }
            put<UpdateUser>("/users/{id}") { }
        }
        KT

      routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source)
      routes.map { |r| {r.verb, r.path, r.receive_type} }.should eq([
        {"POST", "/push/email", "EmailRequest"},
        {"PUT", "/users/{id}", "UpdateUser"},
      ])
    end

    it "recovers a @Resource class whose annotation tree-sitter detached behind comments" do
      # tree-sitter-kotlin mis-parses the first `@Resource` class when it
      # follows a block comment + KDoc that get absorbed into the
      # package_header: the annotation becomes a standalone
      # `prefix_expression` and the class loses its `modifiers`. The
      # collector must pair the orphaned path with the bare class so the
      # resource still resolves (youkube's VideoStream / MainCss).
      source = <<-KT
        package io.ktor.samples.youkube

        /*
         * Typed routes using the [Resources] plugin: https://ktor.io/docs/type-safe-routing.html
         */

        /**
         * A resource for a specific video stream by [id].
         */
        @Resource("/video/{id}")
        class VideoStream(val id: Long)

        @Resource("/video/page/{id}")
        class VideoPage(val id: Long)
        KT

      resources = Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(source)
      resources.map(&.simple_name).sort!.should eq(["VideoPage", "VideoStream"])
    end

    it "resolves resource<T> { } as a prefix wrapper for nested verbs and method/handle" do
      # `resource<Login> { authenticate { post { } }; method(Get) { handle<Login> { } } }`
      # — the typed analogue of `route("/login") { ... }`: nested verbs and
      # the path-less `method(...) { handle { } }` selector bind /login.
      source = <<-KT
        @Resource("/login")
        class Login(val userName: String = "")

        fun Route.login() {
            resource<Login> {
                authenticate("auth") {
                    post { }
                }
                method(HttpMethod.Get) {
                    handle<Login> { }
                }
            }
        }
        KT

      resources = Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(source)
      paths = Noir::TreeSitterKotlinKtorRouteExtractor.compose_resource_paths(resources)
      routes = Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(source, resource_paths: paths)
      routes.map { |r| {r.verb, r.path} }.sort!.should eq([
        {"GET", "/login"},
        {"POST", "/login"},
      ])
    end
  end
end
