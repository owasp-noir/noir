require "../../func_spec.cr"

# cal.com's layout: each sub-router is served by its own
# `pages/api/trpc/<name>/[trpc].ts`, so `slots.getSchedule` answers at
# `/api/trpc/slots/getSchedule` (not `/api/trpc/slots.getSchedule` off the
# client-only appRouter, and not a `{trpc}` catch-all row from Next.js).
expected_endpoints = [
  Endpoint.new("/api/trpc/slots/getSchedule", "GET", [Param.new("from", "", "query")]),
  Endpoint.new("/api/trpc/slots/reserve", "POST"),
  Endpoint.new("/api/trpc/slots/hold", "POST"),
  Endpoint.new("/api/trpc/slots/ping", "GET"),
  Endpoint.new("/api/trpc/me/get", "GET"),
  Endpoint.new("/api/trpc/other/get", "GET"),
  # The router lives in a package outside the scan.
  Endpoint.new("/api/trpc/ext/{trpc}", "GET", [Param.new("trpc", "", "path")]),
  Endpoint.new("/api/trpc/ext/{trpc}", "POST", [Param.new("trpc", "", "path")]),
]

tester = FunctionalTester.new("fixtures/typescript/trpc_next_mounts/", {
  :techs     => 2,
  :endpoints => expected_endpoints.size,
}, expected_endpoints)
tester.perform_tests

describe "tRPC Next.js mounts", tags: "functional" do
  find = ->(method : String, url : String) { tester.endpoints.find! { |ep| ep.method == method && ep.url == url } }
  access = ->(ep : Endpoint) { ep.tags.select { |t| t.tagger == "trpc_auth" }.map { |t| {t.name, t.description} } }

  it "points the handler at what the resolver hands off to" do
    find.call("GET", "/api/trpc/slots/getSchedule").handler.should_not(be_nil).tap do |h|
      h.name.should eq("getScheduleHandler")
      h.path.should_not(be_nil).should end_with("slots/getSchedule.handler.ts")
      h.line.should eq(1)
    end
    find.call("POST", "/api/trpc/slots/reserve").handler.should_not(be_nil).tap do |h|
      h.name.should eq("reserveHandler")
      h.line.should eq(3)
    end
    find.call("POST", "/api/trpc/slots/hold").handler.should_not(be_nil).path.should_not(be_nil).should end_with("slots/hold.handler.ts")
    # An inline resolver is the procedure itself.
    find.call("GET", "/api/trpc/slots/ping").handler.should_not(be_nil).tap do |h|
      h.name.should eq("ping")
      h.path.should_not(be_nil).should end_with("slots/_router.ts")
      h.line.should eq(13)
    end
  end

  it "reads auth from the definitions the procedure builder stacks" do
    access.call(find.call("POST", "/api/trpc/slots/reserve")).should eq([{"auth", "Protected by tRPC authedProcedure (isAuthed)"}])
    access.call(find.call("GET", "/api/trpc/slots/getSchedule")).should eq([{"anonymous", "tRPC publicProcedure admits anonymous callers"}])
    # `.use(rateLimit)` from a package: unread, so neither.
    access.call(find.call("POST", "/api/trpc/slots/hold")).should be_empty
  end

  it "resolves a same-named procedure and router by the import that names them" do
    me = find.call("GET", "/api/trpc/me/get")
    me.details.code_paths.first.path.should end_with("me/procedures/get.ts")
    access.call(me).map(&.[0]).should eq(["auth"])
    other = find.call("GET", "/api/trpc/other/get")
    other.details.code_paths.first.path.should end_with("other/procedures/get.ts")
    access.call(other).map(&.[0]).should eq(["anonymous"])
  end
end
