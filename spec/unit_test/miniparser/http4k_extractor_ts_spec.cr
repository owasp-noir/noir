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
end
