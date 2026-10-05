require "spec"
require "../../../src/miniparsers/kotlin_route_extractor_ts"

# The Kotlin side of the Java-first JAX-RS, Micronaut and Javalin walkers
# (#2856). Each returns the Java extractor's own `Route` type.
private def javalin_config
  Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
    verb_methods: {"get" => "GET", "post" => "POST", "put" => "PUT", "delete" => "DELETE"},
    nest_methods: Set{"path"},
    crud_methods: Set{"crud"},
    query_methods: Set{"queryParam"},
    form_methods: Set{"formParam"},
    header_methods: Set{"header"},
    cookie_methods: Set{"cookie"},
    body_methods: Set{"body"},
    body_typed_methods: Set{"bodyAsClass"},
    websocket_methods: Set{"ws"},
  )
end

private def param_tuples(params : Array(Param))
  params.map { |param| {param.name, param.value, param.param_type} }
end

describe "Noir::TreeSitterKotlinRouteExtractor JAX-RS" do
  it "keeps a class @Path tree-sitter splits off the class" do
    # A bare annotation first, straight after the imports, makes
    # tree-sitter-kotlin parse the annotations as a sibling
    # `prefix_expression` instead of the class's `modifiers`.
    source = <<-KT
      package a

      import x.Y

      @ApplicationScoped
      @Path("/f")
      @Produces(MediaType.APPLICATION_JSON)
      class F(private val s: S) {
          @GET
          fun x() = 1
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_routes(source)
    routes.map { |route| {route.verb, route.path, route.method_name} }.should eq([{"GET", "/f", "x"}])
  end

  it "maps parameter annotations like the Java walker" do
    source = <<-KT
      @Path("/users")
      class UserResource {
          @GET
          @Path("/{id}")
          fun get(
              @PathParam("id") id: Long,
              @QueryParam("q") @DefaultValue("all") q: String?,
              @RestHeader token: String,
              @Context info: UriInfo,
              @BeanParam filter: Filter,
              page: Int,
          ) = 1

          @PUT
          @Consumes(MediaType.APPLICATION_FORM_URLENCODED)
          fun update(payload: Payload) = 2
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_routes(source)
    param_tuples(routes[0].params).should eq([{"q", "all", "query"}, {"token", "", "header"}])
    routes[1].parameter_format.should eq("form")
    param_tuples(routes[1].params).should eq([{"payload", "Payload", "form"}])
  end

  it "follows same-file sub-resource locators without looping" do
    source = <<-KT
      @Path("/a")
      class A {
          @Path("/b")
          fun b(): B = B()
      }

      class B {
          @GET
          fun list() = 1

          @Path("/again")
          fun again(): B = this
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_routes(source)
    routes.map { |route| {route.verb, route.path} }.should eq([{"GET", "/a/b"}])
  end

  it "skips @Path interfaces (MicroProfile REST clients)" do
    source = <<-KT
      @Path("/v2")
      @RegisterRestClient
      interface CountriesService {
          @GET
          @Path("/name/{name}")
          fun getByName(@PathParam("name") name: String): Set<Country>
      }

      @Path("/countries")
      class CountriesResource {
          // a class whose body mentions interface Foo is still a class
          @GET
          fun list() = 1
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_routes(source)
    routes.map(&.path).should eq(["/countries"])
  end

  it "ignores classes without a class-level @Path" do
    source = <<-KT
      class Helper {
          @GET
          fun x() = 1
      }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_routes(source).should be_empty
  end

  it "reads @ApplicationPath" do
    source = <<-KT
      @ApplicationPath("/api")
      class App : Application()
      KT

    Noir::TreeSitter.parse_kotlin(source) do |root|
      Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_application_path_from(root, source).should eq("/api")
    end
  end
end

describe "Noir::TreeSitterKotlinRouteExtractor Micronaut" do
  it "emits controller routes with Micronaut binding rules" do
    source = <<-KT
      package a

      import x.Y

      @Validated
      @Controller("/books")
      @Secured(SecurityRule.IS_ANONYMOUS)
      class BookController {
          @Get("/{id}{?fields}")
          fun show(id: Long, fields: String?, @Header("X-Trace") trace: String?) = 1

          @Get(uris = ["/a", "/b"])
          fun multi(@QueryValue(value = "n", defaultValue = "5") n: Int) = 2

          @CustomHttpMethod(method = "QUERY", value = "/search")
          fun search(@Body("term") term: String) = 3
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_micronaut_routes(source)
    routes.map { |route| {route.verb, route.path} }.should eq([
      {"GET", "/books/{id}"},
      {"GET", "/books/a"},
      {"GET", "/books/b"},
      {"QUERY", "/books/search"},
    ])
    # `@Header("X-Trace")` has no `defaultValue`; the positional name must
    # not be read back as one.
    param_tuples(routes[0].params).should eq([{"fields", "", "query"}, {"X-Trace", "", "header"}])
    param_tuples(routes[1].params).should eq([{"n", "5", "query"}])
    param_tuples(routes[3].params).should eq([{"term", "", "json"}])
  end

  it "requires a class-level @Controller" do
    source = <<-KT
      class NotAController {
          @Get("/x")
          fun x() = 1
      }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_micronaut_routes(source).should be_empty
  end
end

describe "Noir::TreeSitterKotlinRouteExtractor lambda DSL" do
  it "walks trailing lambdas, nesting and method references" do
    source = <<-KT
      fun main() {
          val app = Javalin.create { config ->
              config.router.apiBuilder {
                  path("/api") {
                      get(Users::list)
                      crud("items/{id}", Items())
                  }
              }
          }
          app.post("/login") { ctx ->
              ctx.formParam("user")
              ctx.header("X-Set", "1")
              ctx.cookie("sid")
          }
          app.put("/users/{id}", ::update)
          app.ws("/live") { ws -> }
          headers.put("X-Cache", "none")
      }

      object Users {
          fun list(ctx: Context) { ctx.queryParam("page") }
      }

      fun update(ctx: Context) { ctx.bodyAsClass<User>() }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_lambda_dsl_routes(source, javalin_config)
    routes.map { |route| {route.verb, route.path, route.protocol} }.should eq([
      {"GET", "/api", "http"},
      {"GET", "/api/items", "http"},
      {"POST", "/api/items", "http"},
      {"GET", "/api/items/{id}", "http"},
      {"PATCH", "/api/items/{id}", "http"},
      {"DELETE", "/api/items/{id}", "http"},
      {"POST", "/login", "http"},
      {"PUT", "/users/{id}", "http"},
      {"GET", "/live", "ws"},
    ])
    routes[0].query_params.should eq(["page"])
    routes[6].form_params.should eq(["user"])
    routes[6].header_params.should be_empty
    routes[6].cookie_params.should eq(["sid"])
    routes[7].body_type.should eq("User")
    routes[7].has_body?.should be_true
  end

  it "keeps every route of a fluent chain" do
    source = <<-KT
      fun main() {
          Javalin.create().get("/a") { ctx -> }.post("/b") { ctx -> }.start(7070)
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_lambda_dsl_routes(source, javalin_config)
    routes.map { |route| {route.verb, route.path} }.sort!.should eq([{"GET", "/a"}, {"POST", "/b"}])
  end

  it "does not take receiver-less builder calls for routes" do
    source = <<-KT
      fun health() = buildJsonObject { put("status", "up") }
      val tags = HashMap<String, String>().apply { put("name", "x") }
      KT

    Noir::TreeSitterKotlinRouteExtractor.extract_lambda_dsl_routes(source, javalin_config).should be_empty
  end

  it "resolves Owner::method references to that owner's function" do
    source = <<-KT
      fun main() {
          app.post("/users", UserController::create)
          app.post("/books", BookController::create)
      }

      object UserController {
          fun create(ctx: Context) { ctx.formParam("username") }
      }

      object BookController {
          fun create(ctx: Context) { ctx.formParam("isbn") }
      }
      KT

    routes = Noir::TreeSitterKotlinRouteExtractor.extract_lambda_dsl_routes(source, javalin_config)
    routes.map { |route| {route.path, route.form_params} }.should eq([{"/users", ["username"]}, {"/books", ["isbn"]}])
  end
end
