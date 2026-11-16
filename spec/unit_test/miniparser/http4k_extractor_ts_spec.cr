require "spec"
require "../../../src/miniparsers/http4k_extractor_ts"

describe Noir::TreeSitterHttp4kExtractor do
  it "keeps qualified constants after braces and declaration examples in strings" do
    source = <<-KT
      package com.example
      import org.http4k.routing.routes
      import org.http4k.routing.bind
      import org.http4k.core.Method.GET
      object Paths {
          val example = """
          const val REAL = "/fake"
          object Fake {
          """
          const val BRACE = "조건 }"
          /* } */ const val REAL = "/real"
      }
      val app = routes(Paths.REAL bind GET to handler)
      KT

    constants = Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)
    constants["Paths.REAL"].should eq("/real")
    constants["com.example.Paths.REAL"].should eq("/real")
    Noir::TreeSitterHttp4kExtractor.extract_routes(source).map(&.path).should eq(["/real"])
  end

  it "does not read a declaration inside a string ahead of a live same-line declaration" do
    source = <<-KT
      package com.example
      object Paths {
          log("val PATH = fake"); const val PATH = "/real"
      }
      KT
    Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)["Paths.PATH"].should eq("/real")
  end

  it "keeps cached constant tables private and separates source contents" do
    source = %(object Paths { const val API = "/api" })
    Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)["Paths.API"] = "/changed"
    Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)["Paths.API"].should eq("/api")
    Noir::TreeSitterHttp4kExtractor.extract_string_constants(source.sub("/api", "/other"))["Paths.API"].should eq("/other")
    Noir::ExtractionResultCache.clear_all
    Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)["Paths.API"].should eq("/api")
  end

  it "finds string constants after non-string declarations on the same line" do
    source = %(object Paths { val ignored = 1; const val API = "/api"; const val HEALTH = "/health" })
    constants = Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)
    constants["Paths.API"].should eq("/api")
    constants["Paths.HEALTH"].should eq("/health")
  end

  it "resolves constant and templated route paths" do
    source = <<-KT
      package com.example

      import org.http4k.core.Method.GET
      import org.http4k.core.Response
      import org.http4k.core.Status.Companion.OK
      import org.http4k.routing.bind
      import org.http4k.routing.routes

      object Paths {
          const val API = "/api"
      }

      const val USERS = "/users"

      val app = routes(
          Paths.API bind routes(
              (USERS + "/{id}") bind GET to { req -> Response(OK) },
              "/tenants/$tenantId/items" bind GET to { req -> Response(OK) }
          )
      )
      KT

    constants = Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)
    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(source, constants)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/users/{id}"},
      {"GET", "/api/tenants/{tenantId}/items"},
    ])
  end

  it "does not resolve route paths from project-wide bare constants" do
    source = <<-KT
      import org.http4k.core.Method.GET
      import org.http4k.core.Response
      import org.http4k.core.Status.Companion.OK
      import org.http4k.routing.bind
      import org.http4k.routing.routes

      val app = routes(
          USERS bind GET to { req -> Response(OK) }
      )
      KT

    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(source, {
      "USERS" => "/wrong",
    })
    routes.should be_empty
  end

  it "does not drop qualifiers when resolving route constants" do
    source = <<-KT
      import org.http4k.core.Method.GET
      import org.http4k.core.Response
      import org.http4k.core.Status.Companion.OK
      import org.http4k.routing.bind
      import org.http4k.routing.routes

      val app = routes(
          Other.API bind GET to { req -> Response(OK) }
      )
      KT

    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(source, {
      "API" => "/wrong",
    })
    routes.should be_empty
  end

  it "extracts request reads (query/header/body) from the request object" do
    source = <<-KT
      val app = routes(
          "/x" bind POST to { req: Request ->
              val q = req.query("q")
              val h = req.header("X-Key")
              val b = req.bodyString()
          }
      )
      KT
    route = Noir::TreeSitterHttp4kExtractor.extract_routes(source).first
    route.query_params.should eq(["q"])
    route.header_params.should eq(["X-Key"])
    route.has_body?.should be_true
  end

  it "does not mint request params from Response builder calls" do
    # `Response(...).header(...)` / `.body(...)` WRITE the response, so
    # they must not be read as request inputs — otherwise a bodyless GET
    # gains a phantom body:json and a redirect gains a 'location' header.
    source = <<-KT
      val app = routes(
          "/redirect" bind POST to { req: Request ->
              val target = req.query("target")
              Response(SEE_OTHER).header("location", "/done").body("ignored")
          },
          "/ping" bind GET to { Response(OK).body("pong") }
      )
      KT
    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(source)
    redirect = routes.find! { |r| r.path == "/redirect" }
    redirect.query_params.should eq(["target"])
    redirect.header_params.should be_empty
    redirect.has_body?.should be_false

    ping = routes.find! { |r| r.path == "/ping" }
    ping.has_body?.should be_false
  end

  it "mounts contract routes added inside a prefixed contract block" do
    helper = <<-KT
      import org.http4k.contract.ContractRoute
      import org.http4k.contract.meta
      import org.http4k.core.Method.POST

      fun KnockKnock(): ContractRoute {
          return "/knock" meta {
              summary = "User enters"
          } bindContract POST to userEntry
      }
      KT

    mount = <<-KT
      import org.http4k.contract.contract
      import org.http4k.core.Method.GET
      import org.http4k.routing.bind
      import org.http4k.routing.routes

      val api = "/api" bind routes(
          "/oauth/callback" bind GET to callback,
          contract {
              descriptionPath = "/api-docs"
              routes += KnockKnock()
          }
      )
      KT

    contract_routes = Noir::TreeSitterHttp4kExtractor.extract_contract_route_functions(helper)
    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(mount, contract_routes: contract_routes)

    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/oauth/callback"},
      {"GET", "/api/api-docs"},
      {"POST", "/api/knock"},
    ])
  end

  it "extracts HTTP QUERY routes from bind, nested routes, and bindContract" do
    helper = <<-KT
      import org.http4k.contract.ContractRoute
      import org.http4k.contract.meta
      import org.http4k.core.Method.QUERY

      fun SearchContract(): ContractRoute {
          return "/contract-search" meta {
              summary = "Search items"
          } bindContract Method.QUERY to searchHandler
      }
      KT

    source = <<-KT
      import org.http4k.contract.contract
      import org.http4k.core.Method.QUERY
      import org.http4k.core.Method.GET
      import org.http4k.core.Method
      import org.http4k.routing.bind
      import org.http4k.routing.routes

      val app = routes(
          "/search" bind Method.QUERY to { req -> Response(OK) },
          "/bare-search" bind QUERY to { req -> Response(OK) },
          "/api" bind routes(
              "/nested-search" bind Method.QUERY to { req -> Response(OK) },
              contract {
                  descriptionPath = "/api-docs"
                  routes += SearchContract()
              }
          ),
          "/items" bind routes(
              Method.QUERY to { req -> Response(OK) }
          )
      )
      KT

    contract_routes = Noir::TreeSitterHttp4kExtractor.extract_contract_route_functions(helper)
    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(source, contract_routes: contract_routes)

    routes.map { |r| {r.verb, r.path} }.should eq([
      {"QUERY", "/search"},
      {"QUERY", "/bare-search"},
      {"QUERY", "/api/nested-search"},
      {"GET", "/api/api-docs"},
      {"QUERY", "/api/contract-search"},
      {"QUERY", "/items"},
    ])
  end

  it "ignores a commented-out const val shadowing the live declaration" do
    # `constants[name] ||= value` is first-wins, and the declaration regex used
    # to run over the raw source: a dead constant left above the real one
    # permanently shadowed it, so every route built from it reported a URL that
    # does not exist while the real one was lost.
    source = <<-KT
      package com.example

      import org.http4k.core.Method.GET
      import org.http4k.core.Response
      import org.http4k.core.Status.Companion.OK
      import org.http4k.routing.bind
      import org.http4k.routing.routes

      object Paths {
          // deprecated: const val API = "/old-api"
          /* const val API = "/older-api" */
          const val API = "/api"
      }

      val app = routes(
          Paths.API bind routes(
              "/users" bind GET to { req -> Response(OK) }
          )
      )
      KT

    constants = Noir::TreeSitterHttp4kExtractor.extract_string_constants(source)
    constants["Paths.API"].should eq("/api")

    routes = Noir::TreeSitterHttp4kExtractor.extract_routes(source, constants)
    routes.map { |r| {r.verb, r.path} }.should eq([
      {"GET", "/api/users"},
    ])
  end
end
