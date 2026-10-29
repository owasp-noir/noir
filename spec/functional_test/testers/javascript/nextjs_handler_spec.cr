require "../../func_spec.cr"

# The function serving a Next.js route: the exported verb, or what the
# default / verb export wraps (`defaultResponder(handler)`,
# `withAuth(getHandler)`, `{ GET: Promise.resolve({ default: wrap(h) }) }`).
all_methods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
expected_endpoints = all_methods.map { |m| Endpoint.new("/api/book", m) } +
                     all_methods.map { |m| Endpoint.new("/api/auth/{*nextauth}", m) } +
                     all_methods.map { |m| Endpoint.new("/api/verify", m) } + [
  Endpoint.new("/api/legacy", "GET"),
  Endpoint.new("/api/legacy", "POST"),
  Endpoint.new("/api/me", "GET"),
  Endpoint.new("/api/me", "POST"),
  Endpoint.new("/api/list", "GET"),
]

tester = FunctionalTester.new("fixtures/javascript/nextjs_handler/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "Next.js route handlers", tags: "functional" do
  handler = ->(method : String, url : String) do
    h = tester.endpoints.find! { |ep| ep.method == method && ep.url == url }.handler.should_not(be_nil)
    {h.name, h.path.should_not(be_nil).split("nextjs_handler/").last, h.line}
  end

  it "unwraps the default export to the function it hands the request" do
    all_methods.each { |m| handler.call(m, "/api/book").should eq({"handler", "pages/api/book.ts", 3}) }
    handler.call("GET", "/api/legacy").should eq({"getHandler", "pages/api/legacy.ts", 3})
    handler.call("POST", "/api/legacy").should eq({"default", "pages/api/_post.ts", 1})
    handler.call("GET", "/api/verify").should eq({"handler", "lib/verify.ts", 3})
    # `NextAuth(authOptions)` wraps a config object, not a handler.
    handler.call("GET", "/api/auth/{*nextauth}").should eq({"default", "pages/api/auth/[...nextauth].ts", 8})
  end

  it "unwraps a verb export and reads the wrapped function's body" do
    handler.call("GET", "/api/me").should eq({"getHandler", "app/api/me/route.ts", 3})
    handler.call("POST", "/api/me").should eq({"POST", "app/api/me/route.ts", 10})
    handler.call("GET", "/api/list").should eq({"list", "app/api/list/route.ts", 1})

    me = tester.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/api/me" }
    me.details.code_paths.first.line.should eq(3)
  end
end
