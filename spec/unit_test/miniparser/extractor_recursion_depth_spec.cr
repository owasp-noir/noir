require "spec"

# Each extractor defines its own deep walk over the AST. A
# malicious source file with thousands of nested syntactic
# constructs (e.g., `((((((...))))))` in Kotlin or chained
# `.get(...).get(...)` in TS) would otherwise blow the Crystal
# stack mid-walk and crash the scanner. These specs exercise the
# `Noir::TreeSitter::MAX_AST_DEPTH` guard added to each new
# extractor — the assertion is simply "doesn't raise" since the
# extractor's job is to produce results without crashing on
# adversarial input. Real route shapes never nest beyond ~30
# levels.
require "../../../src/miniparsers/elysia_extractor_ts"
require "../../../src/miniparsers/hapi_extractor_ts"
require "../../../src/miniparsers/http4k_extractor_ts"
require "../../../src/miniparsers/adonisjs_extractor_ts"
require "../../../src/miniparsers/jvm_lambda_dsl_extractor_ts"
require "../../../src/miniparsers/kotlin_ktor_route_extractor_ts"

private NEST = 3000

describe "extractor recursion depth bounds" do
  it "Elysia tolerates a 3000-link chained DSL without crashing" do
    chain = String.build do |io|
      io << "import { Elysia } from 'elysia'\n"
      io << "const app = new Elysia()"
      NEST.times { |i| io << ".get('/r#{i}', () => '#{i}')" }
      io << "\n"
    end
    Noir::TreeSitterElysiaExtractor.extract_routes(chain)
  end

  it "Hapi tolerates 3000 nested object/array configs without crashing" do
    body = String.build do |io|
      io << "server.route("
      NEST.times { io << "[" }
      io << "{ method: 'GET', path: '/x', handler: (r) => r }"
      NEST.times { io << "]" }
      io << ");\n"
    end
    Noir::TreeSitterHapiExtractor.extract_routes(body)
  end

  it "http4k tolerates a 3000-deep nested routes() chain without crashing" do
    body = String.build do |io|
      io << "val app = "
      NEST.times { |i| io << "\"/p#{i}\" bind routes(" }
      io << "\"/leaf\" bind GET to handler"
      NEST.times { io << ")" }
      io << "\n"
    end
    Noir::TreeSitterHttp4kExtractor.extract_routes(body)
  end

  it "AdonisJS tolerates a 3000-link prefix/group chain without crashing" do
    body = String.build do |io|
      io << "import Route from '@ioc:Adonis/Core/Route'\n"
      io << "Route.group(() => { Route.get('/x', 'C.h') })"
      NEST.times { |i| io << ".prefix('/p#{i}')" }
      io << "\n"
    end
    Noir::TreeSitterAdonisJsExtractor.extract_routes(body)
  end

  it "JvmLambdaDsl extractor tolerates 3000 nested path() blocks without crashing" do
    body = String.build do |io|
      io << "class A {\n  void m() {\n"
      NEST.times { |i| io << "    path(\"/p#{i}\", () -> {\n" }
      io << "      get(\"/leaf\", (req, res) -> \"ok\");\n"
      NEST.times { io << "    });\n" }
      io << "  }\n}\n"
    end

    config = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
      verb_methods: {"get" => "GET"},
      nest_methods: Set{"path"},
    )
    Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(body, config)
  end

  it "Ktor route extractor tolerates 3000 nested route() blocks without crashing" do
    body = String.build do |io|
      io << "fun App.cfg() { routing {\n"
      NEST.times { |i| io << "  route(\"/p#{i}\") {\n" }
      io << "    get(\"/leaf\") { call.respondText(\"ok\") }\n"
      NEST.times { io << "  }\n" }
      io << "} }\n"
    end
    Noir::TreeSitterKotlinKtorRouteExtractor.extract_routes(body)
  end
end
