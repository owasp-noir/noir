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
require "../../../src/miniparsers/go_route_extractor_ts"
require "../../../src/miniparsers/kotlin_route_extractor_ts"
require "../../../src/miniparsers/python_callee_extractor"
require "../../../src/miniparsers/js_callee_extractor"
require "../../../src/miniparsers/go_callee_extractor"
require "../../../src/miniparsers/java_callee_extractor"
require "../../../src/miniparsers/rust_callee_extractor_ts"
require "../../../src/miniparsers/ts_contract_extractor"

private NEST = 3000

# The Go cases below nest inside a single expression rather than one
# block per level, so each level costs far less stack than a full walker
# frame — 3000 still fits comfortably. Raised until the unguarded parser
# actually overflowed, so removing the guard fails the spec.
private GO_NEST = 20_000

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

  # `string_expr_text` resolves a route/group prefix built out of `+`
  # concatenation and parentheses. It recurses on the operands via
  # `field(...)`, not through `each_named_child`, so the shared depth
  # guard there never sees it — generated Go with a long concatenated
  # constant used to take the whole scan down with it.
  it "Go route extractor tolerates a #{GO_NEST}-term string concatenation without crashing" do
    body = String.build do |io|
      io << "package main\n\nvar prefix = "
      GO_NEST.times { |i| io << " + " unless i == 0; io << %("a") }
      io << "\n\nfunc reg(r *gin.Engine) {\n  r.GET(prefix, h)\n}\n"
    end
    Noir::TreeSitterGoRouteExtractor.extract_routes(body)
  end

  it "Go route extractor tolerates #{GO_NEST} nested parentheses without crashing" do
    body = "package main\n\nvar prefix = #{"(" * GO_NEST}\"/a\"#{")" * GO_NEST}\n"
    Noir::TreeSitterGoRouteExtractor.extract_routes(body)
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

  # `walk_classes` recursed through raw `ts_node_named_child` indexing and
  # the annotation-value walkers have ~10KB debug frames, so each of these
  # overflowed the stack (a 900-deep `((...))` was already enough).
  {
    "a 20000-link call chain outside any class" => "val big = x#{".f()" * 20_000}\n",
    "20000 nested parentheses in a path"        => "@RestController\nclass P { @GetMapping(#{"(" * 20_000}\"/x\"#{")" * 20_000}) fun x() = 1 }\n",
    "20000 nested brackets in a path"           => "@RestController\nclass P { @GetMapping(#{"[" * 20_000}\"/x\"#{"]" * 20_000}) fun x() = 1 }\n",
    "20000 nested brackets in a method array"   => "@RestController\nclass P { @RequestMapping(value = [\"/x\"], method = #{"[" * 20_000}RequestMethod.GET#{"]" * 20_000}) fun x() = 1 }\n",
  }.each do |label, hostile|
    it "Kotlin Spring extractor tolerates #{label} and keeps the sibling route" do
      body = "#{hostile}\n@RestController\nclass C { @GetMapping(\"/ok\") fun ok() = 1 }\n"
      routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(body)
      routes.map(&.path).should contain("/ok")
    end
  end

  # Effect's `.add(...).prefix(...)` walk used to recurse once per chain
  # link through `field(...)`; 5000 links overflowed the stack.
  it "contract-router extractors tolerate a 20000-link builder chain" do
    effect = "const g = HttpApiGroup.make('g')#{".add(HttpApiEndpoint.get('a', '/a'))" * 20_000}.prefix('/p')\n"
    Noir::TSContractExtractor.effect(effect).first.path.should eq("/p/a")
    orpc = "export const p = os#{".use(m)" * 20_000}.route({ method: 'GET', path: '/x' }).handler(() => 1)\n"
    Noir::TSContractExtractor.orpc(orpc).map(&.path).should eq(["/x"])
    Noir::TSContractExtractor.ts_rest("const c = x#{".use(m)" * 20_000}\n").should be_empty
  end

  # Each link's receiver is the whole chain before it; reading its text
  # to match `HttpApiEndpoint` copied O(n) bytes per link.
  it "Effect stays linear on a long `.add` chain" do
    effect = "const g = HttpApiGroup.make('g')#{".add(HttpApiEndpoint.get('a', '/a'))" * 60_000}\n"
    routes = [] of Noir::TSContractExtractor::Route
    elapsed = Time.measure { routes = Noir::TSContractExtractor.effect(effect) }
    routes.size.should eq(60_000)
    elapsed.should be < 3.seconds
  end
end

# The callee extractors rebuild an `a.b.c` receiver by recursing once per
# chain link through `field(...)`, outside `each_named_child`'s guard. A
# generated `x.b.b.b…(1)` chain overflowed the stack under
# `--include-callee` and aborted the whole scan with no output.
private CALLEE_CHAIN = "x#{".b" * 100_000}(1)"

describe "callee extractor receiver-chain depth bounds" do
  it "Python" do
    Noir::PythonCalleeExtractor.calls_in("def h():\n    return #{CALLEE_CHAIN}\n")
  end

  it "JavaScript" do
    Noir::JSCalleeExtractor.callees_for_function_body(" #{CALLEE_CHAIN}; ", "a.js", 1)
  end

  it "Go" do
    fn = Noir::GoCalleeExtractor::FunctionBody.new("func h() { #{CALLEE_CHAIN} }", "a.go", 0)
    Noir::GoCalleeExtractor.callees_in_body(fn)
  end

  it "Java" do
    source = "class A { String h() { return #{CALLEE_CHAIN}; } }"
    Noir::TreeSitter.parse_java(source) do |root|
      Noir::JavaCalleeExtractor.callees_in_body(root, source, "A.java")
    end
  end

  it "Rust" do
    Noir::RustCalleeExtractorTS.callees_for_body_text("#{CALLEE_CHAIN};", "a.rs", 1)
  end
end
