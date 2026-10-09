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

  it "maps methods under every path of a multi-path class-level mapping" do
    source = <<-KT
      package com.example

      @RestController
      @RequestMapping(value = ["/v1", "/v2"])
      class A {
          @GetMapping("/a")
          fun a(): String = ""
      }

      @RestController
      @RequestMapping(["/q1", "/q2"])
      class B : Api {
          @GetMapping("/b")
          fun b(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/v1/a"},
      {"GET", "/v2/a"},
      {"GET", "/q1/b"},
      {"GET", "/q2/b"},
    ])

    Noir::TreeSitter.parse_kotlin(source) do |root|
      implementations = Noir::TreeSitterKotlinRouteExtractor.extract_controller_interface_implementations_from(root, source)
      implementations.map { |impl| {impl.class_name, impl.path} }.should eq([
        {"B", "/q1"},
        {"B", "/q2"},
      ])
    end
  end

  it "walks nested multi-path classes once and caps the prefix product" do
    # Each level doubles the prefixes. Re-walking a nested class once per
    # outer prefix made this 2^40 walks; it must finish at once with the
    # product capped.
    source = String.build do |io|
      40.times { io << "@RequestMapping([\"/a\", \"/b\"])\nclass O {\n" }
      io << "@GetMapping(\"/x\")\nfun x() = 1\n"
      40.times { io << "}\n" }
    end

    elapsed = Time.measure do
      routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
      routes.size.should eq(Noir::TreeSitterKotlinRouteExtractor::MAX_CLASS_PREFIXES)
      routes.first.path.should eq("#{"/a" * 40}/x")
    end
    elapsed.should be < 5.seconds
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

  it "resolves Kotlin string constants in mapping paths" do
    source = <<-KT
      package com.example

      object ApiPaths {
          const val PREFIX = "/api"
      }

      const val USERS = "/users"

      @RequestMapping(ApiPaths.PREFIX)
      class A {
          @GetMapping(USERS + "/{id}")
          fun x(): String = ""

          @PostMapping(path = arrayOf(USERS, "/accounts"))
          fun y(): String = ""
      }
      KT

    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/users/{id}"},
      {"POST", "/api/users"},
      {"POST", "/api/accounts"},
    ])
  end

  it "does not resolve simple mapping constants from the global index" do
    source = <<-KT
      package com.example

      @RequestMapping("/api")
      class A {
          @GetMapping(USERS)
          fun x(): String = ""
      }
      KT

    constants = {"USERS" => "/wrong"} of String => String
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)
    routes.map(&.path).should_not contain("/api/wrong")
  end

  it "resolves fully-qualified mapping constants from the global index" do
    source = <<-KT
      package com.example

      @RequestMapping(com.example.ApiPaths.PREFIX)
      class A {
          @GetMapping("/users")
          fun x(): String = ""
      }
      KT

    constants = {"com.example.ApiPaths.PREFIX" => "/api"} of String => String
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)
    routes.map(&.path).should eq(["/api/users"])
  end

  it "treats a bare path identifier argument as a positional constant" do
    source = <<-KT
      package com.example

      import com.example.MovieController.Companion.path

      @RestController
      @RequestMapping(path)
      class MovieController {
          @GetMapping
          fun list(): String = ""

          companion object {
              const val path = "/api/movies"
          }
      }
      KT

    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/movies"},
    ])
  end

  it "collapses an empty method path onto the class prefix" do
    # Kotlin Spring controllers routinely do
    # `@RequestMapping("/api/article")` on the class and `@GetMapping`
    # (no path arg) on a method. Spring absorbs the empty segment, so
    # the handler maps to `/api/article` (no trailing slash). Matches
    # the Java Spring behaviour.
    source = <<-KT
      @RequestMapping("/api/article")
      class ArticleController {
          @GetMapping
          fun list(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map(&.path).should eq(["/api/article"])
  end

  it "keeps same-line WebFlux functional router lambda callees" do
    source = <<-KT
      class RouterConfiguration {
          fun routes(auditService: AuditService) = coRouter {
              GET("/audit") { auditService.record(); ServerResponse.ok().build() }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)

    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/audit"},
    ])
    routes.first.inline_callees.map { |callee| {callee[:name], callee[:line]} }.should contain({
      "auditService.record",
      3,
    })
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

  it "extracts Spring WebFlux functional router routes and handler references" do
    source = <<-KT
      package com.example

      @Configuration
      class RouterConfiguration(private val constructorHandler: ConstructorHandler) {
          @Bean
          fun routes(postHandler: PostHandler) = coRouter {
              "/posts".nest {
                  GET("", postHandler::all)
                  GET("/{id}", postHandler::get)
                  POST("", postHandler::create)
                  PUT("/{id}", postHandler::update)
                  DELETE("/{id}", postHandler::delete)
              }
              GET("/constructor", constructorHandler::show)
          }
      }

      @Component
      class PostHandler {
          suspend fun all(req: ServerRequest): ServerResponse = ok().buildAndAwait()
      }

      @Component
      class ConstructorHandler {
          suspend fun show(req: ServerRequest): ServerResponse = ok().buildAndAwait()
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.class_name, r.method_name, r.handler_reference} }.should eq([
      {"GET", "/posts", "PostHandler", "all", "postHandler::all"},
      {"GET", "/posts/{id}", "PostHandler", "get", "postHandler::get"},
      {"POST", "/posts", "PostHandler", "create", "postHandler::create"},
      {"PUT", "/posts/{id}", "PostHandler", "update", "postHandler::update"},
      {"DELETE", "/posts/{id}", "PostHandler", "delete", "postHandler::delete"},
      {"GET", "/constructor", "ConstructorHandler", "show", "constructorHandler::show"},
    ])
  end

  it "ignores commented Spring WebFlux functional router calls" do
    source = <<-KT
      package com.example

      class RouterConfiguration {
          fun routes(postHandler: PostHandler) = coRouter {
              // "/commented".nest {
              //   GET("/ghost", postHandler::ghost)
              // }
              val documentation = "GET(\\"/string-only\\", postHandler::ghost)"
              "/posts".nest {
                  GET("", postHandler::all)
              }
          }
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.handler_reference} }.should eq([
      {"GET", "/posts", "postHandler::all"},
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

  it "expands $VAR interpolations inside constant values (transitively)" do
    consts = {
      "PUBLIC_URL"  => "/public",
      "STATIC_URL"  => "$PUBLIC_URL/static",
      "ACCOUNT_URL" => "${PUBLIC_URL}/account",
      "PROP"        => "${spring.config}", # Spring property placeholder stays untouched
    }
    expanded = Noir::TreeSitterKotlinRouteExtractor.expand_constant_interpolations(consts)
    expanded["STATIC_URL"].should eq("/public/static")
    expanded["ACCOUNT_URL"].should eq("/public/account")
    expanded["PROP"].should eq("${spring.config}")
  end

  it "resolves template and + concatenation constants within one file" do
    source = <<-KT
      package demo

      object Routes {
          const val BASE = "/base"
          const val ITEM = "$BASE/item"
          const val ITEM2 = BASE + "/item2" // trailing comment
          const val ITEM3 = "${BASE}/item3"
          const val ITEM4 = Routes.ITEM2 + "/x" + BASE;
      }

      @RestController
      class C {
          @GetMapping(Routes.ITEM)
          fun a(): String = ""
          @GetMapping(Routes.ITEM2)
          fun b(): String = ""
          @GetMapping(Routes.ITEM3)
          fun c(): String = ""
          @GetMapping(Routes.ITEM4)
          fun d(): String = ""
      }
      KT
    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)
    routes.map(&.path).should eq(["/base/item", "/base/item2", "/base/item3", "/base/item2/x/base"])
  end

  it "resolves a Type.NAME mapping constant from the cross-file index" do
    source = <<-KT
      @RestController
      class C {
          @GetMapping(Routes.ITEM)
          fun a(): String = ""
      }
      KT
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, {"Routes.ITEM" => "/base/item"})
    routes.map(&.path).should eq(["/base/item"])
  end

  it "expands a file's constants against another file's through the fallback" do
    local = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(<<-KT)
      const val ITEM = "$BASE/item"
      const val ITEM2 = Paths.BASE + "/item2"
      KT
    local["ITEM2"].should eq("${Paths.BASE}/item2")
    expanded = Noir::TreeSitterKotlinRouteExtractor.expand_constant_interpolations(
      local, {"BASE" => "/base", "Paths.BASE" => "/base"})
    expanded["ITEM"].should eq("/base/item")
    expanded["ITEM2"].should eq("/base/item2")
  end

  it "keeps non-constant concatenations and plain vals out of the table" do
    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(<<-KT)
      val dynamic = prefix + "/x"
      const val CALL = BASE + build("/y")
      const val ONE = BASE
      KT
    constants.has_key?("dynamic").should be_false
    constants.has_key?("CALL").should be_false
    constants.has_key?("ONE").should be_false
  end

  it "leaves a self-doubling template chain unexpanded instead of growing it" do
    lines = ["const val K0 = \"/aaaaaaaaaaaaaaaa\""]
    (1...60).each { |i| lines << "const val K#{i} = \"$K#{i - 1}$K#{i - 1}\"" }
    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(lines.join("\n"))
    constants.each_value { |value| value.size.should be <= Noir::TreeSitterKotlinRouteExtractor::MAX_EXPANDED_CONSTANT_SIZE }
    constants["K2"].should eq("/aaaaaaaaaaaaaaaa" * 4)
  end

  it "composes a class-level @RequestMapping prefix from a cross-file bare const" do
    source = <<-KT
      @RestController
      @RequestMapping(path = [PUBLIC_URL])
      class AuthController {
          @PostMapping("/register")
          fun register(): String = ""
      }
      KT
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, {"PUBLIC_URL" => "/public"})
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "/public/register"},
    ])
  end

  it "resolves a $CONST interpolation inside an inline mapping path literal" do
    source = <<-KT
      @RestController
      class VersionController {
          @GetMapping(path = ["$PUBLIC_URL/version"])
          fun version(): String = ""
      }
      KT
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, {"PUBLIC_URL" => "/public"})
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/public/version"},
    ])
  end

  it "skips @FeignClient interfaces (outbound clients, not server routes)" do
    source = <<-KT
      @FeignClient(value = "example-api")
      interface ExampleApi {
          @RequestMapping(method = [RequestMethod.POST], value = ["/example/example-api"])
          fun example(): String
      }

      @RestController
      @RequestMapping("/real")
      class RealController {
          @GetMapping("/ping")
          fun ping(): String = "pong"
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/real/ping"},
    ])
  end

  it "extracts interface routes and concrete controller implementations" do
    source = <<-KT
      package com.example

      @RequestMapping("/api/users")
      interface UserApi {
          @GetMapping("/{id}")
          fun show(@PathVariable id: String): String
      }

      @RestController
      class UserController : UserApi {
          override fun show(id: String): String = service.show(id)
      }
      KT

    Noir::TreeSitter.parse_kotlin(source) do |root|
      interface_routes = Noir::TreeSitterKotlinRouteExtractor.extract_interface_routes_from(root, source)
      interface_routes["UserApi"].map { |r| {r.verb, r.path, r.class_name, r.method_name} }.should eq([
        {"GET", "/api/users/{id}", "UserApi", "show"},
      ])

      implementations = Noir::TreeSitterKotlinRouteExtractor.extract_controller_interface_implementations_from(root, source)
      implementations.map { |impl| {impl.class_name, impl.interface_names, impl.path} }.should eq([
        {"UserController", ["UserApi"], ""},
      ])
    end
  end

  it "recovers routes from non-abstract controllers with split constructor annotations" do
    source = <<-KT
      package com.example

      @RestController
      @RequestMapping("/api")
      class UserController
      @Autowired constructor(private val service: UserService) {
          @GetMapping("/{id}")
          fun show(@PathVariable id: Long): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.class_name, r.method_name} }.should eq([
      {"GET", "/api/{id}", "UserController", "show"},
    ])
  end

  it "does not recover routes from abstract split-constructor base controllers" do
    source = <<-KT
      package com.example

      @RestController
      abstract class AbstractController<T : Any>
      @Autowired constructor(private val service: Service<T>) {
          @GetMapping("/{id}")
          fun show(@PathVariable id: Long): String = ""
      }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_routes(source).should be_empty
  end

  # tree-sitter-kotlin can parse an annotated class that is followed by
  # another class as `prefix_expression > infix_expression` (`class`,
  # the name and a `lambda_literal` body) with no ERROR node.
  it "recovers routes from a class misparsed as an annotated infix expression" do
    source = <<-KT
      package com.ex

      import org.springframework.web.bind.annotation.*

      @RestController
      @RequestMapping("/k1")
      class K1 {
          @GetMapping("/x")
          fun x(): String = ""
      }

      @RestController
      @RequestMapping("/k2")
      class K2 {
          @GetMapping("/y")
          fun y(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.class_name, r.method_name} }.should eq([
      {"GET", "/k1/x", "K1", "x"},
      {"GET", "/k2/y", "K2", "y"},
    ])
  end

  it "reads a keyword class prefix from a class misparsed as an infix expression" do
    source = <<-KT
      package com.ex

      @RestController
      @RequestMapping(value = ["/k1"], produces = ["application/json"])
      class K1 {
          @GetMapping("/x")
          fun x(): String = ""
      }

      @RestController
      class K2 {
          @GetMapping("/y")
          fun y(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.class_name} }.should eq([
      {"GET", "/k1/x", "K1"},
      {"GET", "/y", "K2"},
    ])
  end

  it "does not recover routes from a misparsed @FeignClient class" do
    source = <<-KT
      package com.ex

      import org.springframework.web.bind.annotation.*

      @FeignClient(name = "remote")
      @RequestMapping("/k1")
      class K1 {
          @GetMapping("/x")
          fun x(): String = ""
      }

      @RestController
      class K2 {
          @GetMapping("/y")
          fun y(): String = ""
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source)
    routes.map { |r| {r.verb, r.path, r.class_name} }.should eq([
      {"GET", "/y", "K2"},
    ])
  end

  it "extracts Spring GraphQL query and mutation mappings" do
    source = <<-KT
      package com.example

      const val ARTICLE_ID_ARG = "articleId"

      @Controller
      class GraphqlController(private val service: ArticleService) {
          @QueryMapping
          fun article(@Argument id: String): Article = service.findArticle(id)

          @MutationMapping("createArticle")
          fun create(@Argument("input") request: CreateArticleInput): Article =
              service.createArticle(request)

          @MutationMapping
          fun addComment(@Argument(name = ARTICLE_ID_ARG) id: String, @Argument input: CommentInput): Comment =
              service.addComment(id, input)

          @SchemaMapping
          fun author(article: Article): User =
              service.findAuthor(article.authorId)

          @SchemaMapping("comments")
          fun articleComments(article: Article): List<Comment> =
              service.findComments(article.id)

          @SchemaMapping(typeName = "Comment", field = "author")
          fun commentAuthor(comment: Comment): User =
              service.findAuthor(comment.authorId)
      }
      KT

    Noir::TreeSitter.parse_kotlin(source) do |root|
      routes = Noir::TreeSitterKotlinRouteExtractor.extract_graphql_routes_from(root, source)
      routes.map do |route|
        {
          route.operation_keyword,
          route.root_kind,
          route.field_name,
          route.class_name,
          route.method_name,
          route.arguments.map { |arg| {arg[:name], arg[:type]} },
        }
      end.should eq([
        {"query", "Query", "article", "GraphqlController", "article", [{"id", "String"}]},
        {"mutation", "Mutation", "createArticle", "GraphqlController", "create", [{"input", "CreateArticleInput"}]},
        {"mutation", "Mutation", "addComment", "GraphqlController", "addComment", [{"articleId", "String"}, {"input", "CommentInput"}]},
        {"field", "Article", "author", "GraphqlController", "author", [] of Tuple(String, String)},
        {"field", "Article", "comments", "GraphqlController", "articleComments", [] of Tuple(String, String)},
        {"field", "Comment", "author", "GraphqlController", "commentAuthor", [] of Tuple(String, String)},
      ])
    end
  end

  it "keeps every entry of an arrayOf() STOMP destination prefix" do
    source = <<-KT
      class WsConfig {
          override fun configureMessageBroker(registry: MessageBrokerRegistry) {
              registry.setApplicationDestinationPrefixes(arrayOf("/app", "/topic"))
          }
      }
      KT

    prefixes = Noir::TreeSitterKotlinRouteExtractor.extract_stomp_application_prefixes(source)
    prefixes.should eq(["/app", "/topic"])
  end

  it "ignores a commented-out const val shadowing the live declaration" do
    # `constants[name] ||= value` means first-wins, and the declaration regex
    # used to run over the raw source: a dead constant left above the real one
    # permanently shadowed it, so every route built from it reported a URL
    # that does not exist while the real one was lost.
    source = <<-KT
      package com.example

      object GatewayPolicy {
          // deprecated: const val MCP_ENDPOINT_PATH = "/old-mcp"
          /* const val MCP_ENDPOINT_PATH = "/older-mcp" */
          const val MCP_ENDPOINT_PATH = "/mcp"
      }
      KT

    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(source)
    constants["MCP_ENDPOINT_PATH"].should eq("/mcp")
    constants["GatewayPolicy.MCP_ENDPOINT_PATH"].should eq("/mcp")
    constants["com.example.GatewayPolicy.MCP_ENDPOINT_PATH"].should eq("/mcp")
  end

  it "keeps a gateway PredicateSpec helper readable behind a non-ASCII comment" do
    # The comment mask emitted one space per *byte*; `MatchData#end` is a char
    # offset, so a multi-byte comment on the helper line shifted every offset
    # after it and the expression tail was over-trimmed away.
    source = <<-KT
      package com.example

      object GatewayPolicy {
          const val MCP_ENDPOINT_PATH = "/mcp"
      }

      class GatewayRouteConfig {
          fun customRouteLocator(builder: RouteLocatorBuilder): RouteLocator {
              val routesBuilder = builder.routes()
              routesBuilder.route("post") { predicateSpec ->
                  predicateSpec.isPostRequestToMcpEndpoint().uri("no://op")
              }
              return routesBuilder.build()
          }

          /* MCP 엔드포인트 전용 조건 */ private fun PredicateSpec.isPostRequestToMcpEndpoint() = method(HttpMethod.POST).and().path(GatewayPolicy.MCP_ENDPOINT_PATH)
      }
      KT

    constants = Noir::TreeSitterKotlinRouteExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(source, constants)

    routes.map { |r| {r.verb, r.path} }.should eq([
      {"POST", "/mcp"},
    ])
  end

  it "does not turn a commented-out STOMP addEndpoint into a real endpoint" do
    source = <<-KT
      package com.example

      class WsConfig {
          override fun registerStompEndpoints(registry: StompEndpointRegistry) {
              // registry.addEndpoint("/ws-legacy-removed").withSockJS()
              registry.addEndpoint("/ws").withSockJS()
          }
      }
      KT

    routes = [] of Noir::TreeSitterKotlinRouteExtractor::Route
    Noir::TreeSitter.parse_kotlin(source) do |root|
      routes = Noir::TreeSitterKotlinRouteExtractor.extract_stomp_routes_from(root, source)
    end

    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/ws"},
    ])
  end

  it "does not read a STOMP application prefix out of a comment" do
    source = <<-KT
      class WsConfig {
          override fun configureMessageBroker(registry: MessageBrokerRegistry) {
              // registry.setApplicationDestinationPrefixes("/legacy")
              registry.setApplicationDestinationPrefixes("/app")
          }
      }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_stomp_application_prefixes(source).should eq(["/app"])
  end

  # The vendored scanner used to abort() the whole process once string
  # templates nested past its 1024-entry delimiter stack.
  it "survives string templates nested deeper than the scanner stack" do
    depth = 1100
    nested = %(") + %(${") * depth + "x" + %("}) * depth + %(")
    source = "@RestController\nclass Deep {\n    @GetMapping(#{nested})\n    fun deep(): String = \"\"\n}\n"
    Noir::TreeSitterKotlinRouteExtractor.extract_routes(source).should be_a(Array(Noir::TreeSitterKotlinRouteExtractor::Route))
  end
end
