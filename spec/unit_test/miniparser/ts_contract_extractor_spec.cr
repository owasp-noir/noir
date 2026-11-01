require "../../spec_helper"
require "../../../src/miniparsers/ts_contract_extractor"

describe Noir::TSContractExtractor do
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
