require "../../func_spec.cr"

# h3 readers beyond getQuery/readBody, and locals that only look like reads:
# `db.query.users` is no `query` field, a Supabase `data` is no body, and a
# validator's own `.min(1)` is no query field. `ping.get.dev.ts` carries
# Nitro's environment suffix.
expected_endpoints = [
  Endpoint.new("/api/fn-inputs", "POST", [
    Param.new("authorization", "", "header"),
    Param.new("x-legacy", "", "header"),
    Param.new("x-tenant", "", "header"),
    Param.new("sid", "", "cookie"),
    Param.new("debug", "", "query"),
    Param.new("title", "", "form"),
  ]),
  Endpoint.new("/api/fp-data", "POST", [Param.new("name", "", "body")]),
  Endpoint.new("/api/fp-drizzle", "GET", [Param.new("page", "", "query")]),
  Endpoint.new("/api/fp-validated", "GET", [Param.new("search", "", "query")]),
  Endpoint.new("/api/ping", "GET"),
]

tester = FunctionalTester.new("fixtures/javascript/nuxtjs_h3_readers/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

it "reads no params from lookalike locals", tags: "functional" do
  {"/api/fp-data" => ["name"], "/api/fp-drizzle" => ["page"], "/api/fp-validated" => ["search"]}.each do |url, names|
    tester.endpoints.find! { |endpoint| endpoint.url == url }.params.map(&.name).should eq(names)
  end
end

it "reports the default-exported handler's line below the imports", tags: "functional" do
  tester.endpoints.find! { |endpoint| endpoint.url == "/api/fp-drizzle" }.details.code_paths.first.line.should eq(3)
end
