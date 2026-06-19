require "spec"
require "../../../src/miniparsers/http4k_extractor_ts"

describe Noir::TreeSitterHttp4kExtractor do
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
end
