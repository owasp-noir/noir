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
end
