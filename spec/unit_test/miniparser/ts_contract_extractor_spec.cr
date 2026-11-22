require "../../spec_helper"
require "../../../src/miniparsers/ts_contract_extractor"

describe Noir::TSContractExtractor do
  it "reads Hono documentation calls without promoting strings, comments or other receivers" do
    source = <<-TS
      const app = new OpenAPIHono()
      const example = "app.doc('/fake')"
      const factory = `const fake = new OpenAPIHono(); fake.doc('/fake-app')`
      // app.doc('/comment')
      app.doc('/openapi.json', {})
      app.doc31(`/openapi31.json`, {})
      db.doc('users/1')
      const direct = new OpenAPIHono<Env>()
        .doc('/direct', {})
        .doc31('/direct31', {})
      TS

    routes = Noir::TSContractExtractor.hono_openapi(source, "app.ts")
    routes.map { |r| {r.method, r.path} }.sort!.should eq([
      {"GET", "/direct"}, {"GET", "/direct31"}, {"GET", "/openapi.json"}, {"GET", "/openapi31.json"},
    ])
    routes.find! { |r| r.path == "/openapi.json" }.line.should eq(5)
  end

  it "reads documentation in app factories alongside createRoute contracts" do
    source = <<-TS
      const route = createRoute({ method: 'get', path: '/items' })
      function factory() {
        const app = new OpenAPIHono().basePath('/api')
        app.openapi(route, handler)
        app.doc('/doc', {})
        return app
      }
      TS

    Noir::TSContractExtractor.hono_openapi(source, "app.ts").map(&.path).should eq(["/items", "/doc"])
  end

  it "keeps an unread registration visible without borrowing a shadowed app" do
    source = <<-TS
      const app = new OpenAPIHono()
      const served = createRoute({ method: 'get', path: '/served' })
      const other = createRoute({ method: 'get', path: '/maybe' })
      app.openapi(served, handler)
      function attach(app) { app.openapi(other, handler) }
      TS

    file = Noir::TSContractExtractor.hono_file(source, "app.ts")
    routes = Noir::TSContractExtractor.hono_endpoints([file]) { nil }
    routes.map { |r| {r.route.path, r.line, r.unresolved} }.should eq([
      {"/served", 4, false}, {"/maybe", 3, true},
    ])
  end

  it "retains every candidate for a dynamic descriptor selection" do
    source = <<-TS
      const app = new OpenAPIHono()
      const first = createRoute({ method: 'get', path: '/a' })
      const second = createRoute({ method: 'post', path: '/b' })
      app.openapi(flag ? first : second, handler)
      TS

    file = Noir::TSContractExtractor.hono_file(source, "app.ts")
    routes = Noir::TSContractExtractor.hono_endpoints([file]) { nil }
    routes.map { |r| {r.route.path, r.unresolved} }.should eq([{"/a", true}, {"/b", true}])
  end

  it "looks through as / satisfies in a ts-rest contract" do
    source = <<-TS
      const BASE: string = '/v1'
      export const contract = c.router({
        get: { method: 'GET' as const, path: `${BASE}/posts` as const, query: z.object({ q: z.string() }) },
        create: { method: 'POST', path: '/posts', body: z.object({ title: z.string() }) } satisfies AppRoute,
      } as const, { pathPrefix: '/api' as const })
      TS

    routes = Noir::TSContractExtractor.ts_rest(source, "contract.ts")
    routes.map { |r| {r.method, r.path} }.should eq([{"GET", "/api/v1/posts"}, {"POST", "/api/posts"}])
    routes[0].params.should eq([{"q", "query"}])
    routes[1].params.should eq([{"title", "json"}])
  end

  it "reads an oRPC route config wrapped in as const" do
    source = "export const p = os.$context<{ user: U }>().route({ method: 'GET', path: '/x/{id}' } as const).input(z.object({ q: z.string() }))"
    routes = Noir::TSContractExtractor.orpc(source, "router.ts")
    routes.map { |r| {r.method, r.path} }.should eq([{"GET", "/x/{id}"}])
  end

  it "reads Effect schema class fields through the TypeScript extends clause" do
    source = <<-TS
      class Body extends Schema.Class<Body>("Body")({ name: Schema.String }) {}
      const Users = HttpApiGroup.make("users").add(HttpApiEndpoint.post("create", "/users").setPayload(Body))
      TS

    routes = Noir::TSContractExtractor.effect(source, "api.ts")
    routes.map { |r| {r.method, r.path} }.should eq([{"POST", "/users"}])
    routes[0].params.should eq([{"name", "json"}])
  end
end
