require "spec"
require "../../../src/miniparsers/kotlin_route_extractor_ts"

describe Noir::TreeSitterKotlinRouteExtractor do
  it "composes class-level and method-level mapping prefixes" do
    source = <<-KT
      package com.example

      @RestController
      @RequestMapping("/api")
      class UserController {
          @GetMapping("/users")
          fun list(): String = ""

          @PostMapping("/users")
          fun create(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.method_name} }.should eq([
      {"GET", "/api/users", "list"},
      {"POST", "/api/users", "create"},
    ])
  end

  it "handles value = / path = keyword arguments" do
    source = <<-KT
      class K {
          @GetMapping(value = "/x")
          fun a(): String = ""

          @PostMapping(path = "/y", produces = ["application/json"])
          fun b(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/x"},
      {"POST", "/y"},
    ])
  end

  it "derives the verb from RequestMethod for generic @RequestMapping" do
    source = <<-KT
      class M {
          @RequestMapping(value = "/get", method = [RequestMethod.GET])
          fun a(): String = ""

          @RequestMapping(value = "/post", method = [RequestMethod.POST])
          fun b(): String = ""

          @RequestMapping("/default")
          fun c(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/get"},
      {"POST", "/post"},
      {"GET", "/default"},
    ])
  end

  it "fans out method arrays in @RequestMapping" do
    source = <<-KT
      @RequestMapping("items")
      class C {
          @RequestMapping("/multiple/methods", method = [RequestMethod.GET, RequestMethod.POST])
          fun c(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "items/multiple/methods"},
      {"POST", "items/multiple/methods"},
    ])
  end

  it "fans out path arrays on mapping annotations" do
    source = <<-KT
      class A {
          @GetMapping(value = ["/a", "/b"])
          fun x(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/a"},
      {"GET", "/b"},
    ])
  end

  it "emits prefix/ when the method path is empty" do
    # Kotlin Spring controllers routinely do
    # `@RequestMapping("/api/article")` on the class and `@GetMapping`
    # (no path arg) on a method, expecting `/api/article/` for the
    # handler. Matches the Java Spring behaviour pinned down in #1291.
    source = <<-KT
      @RequestMapping("/api/article")
      class ArticleController {
          @GetMapping
          fun list(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/api/article/"])
  end

  it "extracts Spring Cloud Gateway PredicateSpec helper routes" do
    source = <<-KT
      package com.example

      object GatewayPolicy {
          const val MCP_ENDPOINT_PATH = "/mcp"
      }

      class GatewayRouteConfig {
          fun customRouteLocator(builder: RouteLocatorBuilder): RouteLocator {
              val routesBuilder = builder.routes()
              routesBuilder.route("post") { predicateSpec ->
                  predicateSpec
                      .order(0)
                      .isPostRequestToMcpEndpoint().and()
                      .uri("no://op")
              }
              routesBuilder.route("get") { predicateSpec ->
                  predicateSpec.isGetRequestToMcpEndpoint().uri("no://op")
              }
              routesBuilder.route("delete") { predicateSpec ->
                  predicateSpec.isDeleteRequestToMcpEndpoint().uri("no://op")
              }
              // predicateSpec.isCommentOnlyRequestToMcpEndpoint()
              val documentation = "predicateSpec.isCommentOnlyRequestToMcpEndpoint()"
              return routesBuilder.build()
          }

          private fun PredicateSpec.isPostRequestToMcpEndpoint() =
              method(HttpMethod.POST).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)

          private fun PredicateSpec.isGetRequestToMcpEndpoint(): BooleanSpec = method(HttpMethod.GET).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)

          private fun PredicateSpec.isDeleteRequestToMcpEndpoint() =
              method(HttpMethod.DELETE).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)

          private fun PredicateSpec.isCommentOnlyRequestToMcpEndpoint() =
              method(HttpMethod.PATCH).and().path("/commented")
      }
      KT

    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)

    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "/mcp"},
      {"GET", "/mcp"},
      {"DELETE", "/mcp"},
    ])
  end

  it "ignores non-mapping annotations" do
    source = <<-KT
      class X {
          @Deprecated("old")
          fun legacy(): Unit = Unit
      }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_routes(source).should be_empty
  end
end
