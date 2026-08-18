require "../../func_spec.cr"

# Two Nuxt apps under one scan base, each with its own `server/routes/auth.ts`.
# The analyzer used to dedup on (url, method) against the shared result array
# and throw the loser away, so one app's `auth.ts` erased the other's: params,
# callees and code path included. Within `apps/admin`, `notes.ts` and
# `notes/index.ts` resolve to the same Nitro route and lost each other the same
# way.
expected_endpoints = [
  # Both apps' handlers, folded by the optimizer into the one URL they serve —
  # each app deploys at its own base, so neither route is `/apps/<name>/auth`.
  Endpoint.new("/auth", "ANY", [
    Param.new("admin_session", "", "cookie"),
    Param.new("site_session", "", "cookie"),
  ]),

  # `notes.ts` + `notes/index.ts`: one route, both files' query params.
  Endpoint.new("/api/notes", "ANY", [
    Param.new("sort", "", "query"),
    Param.new("cursor", "", "query"),
  ]),

  # A route only one app serves, to pin that folding does not over-merge.
  Endpoint.new("/api/posts", "GET", [
    Param.new("tag", "", "query"),
  ]),
]

tester = FunctionalTester.new("fixtures/javascript/nuxtjs_monorepo/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)

tester.perform_tests

describe "nuxtjs monorepo route folding" do
  it "keeps every contributing file in code_paths" do
    fixture = "./spec/functional_test/fixtures/javascript/nuxtjs_monorepo"

    {
      {"/auth", "ANY", ["apps/admin/server/routes/auth.ts", "apps/site/server/routes/auth.ts"]},
      {"/api/notes", "ANY", ["apps/admin/server/api/notes.ts", "apps/admin/server/api/notes/index.ts"]},
    }.each do |(url, method, sources)|
      endpoint = tester.endpoints.find { |e| e.url == url && e.method == method } ||
                 fail("MISSING ENDPOINT [#{method}::#{url}] in tester: nuxtjs_monorepo")
      paths = endpoint.details.code_paths.map { |code_path| File.expand_path(code_path.path) }

      sources.each do |source|
        paths.should contain File.expand_path(File.join(fixture, source))
      end
    end
  end
end
