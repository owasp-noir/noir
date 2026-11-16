require "../../func_spec.cr"
require "../../../../src/cli/inspect"

# Fastify keeps the handler in the route's options object: the full
# declaration `fastify.route({ ..., handler })` and the shorthand
# `fastify.post(url, { schema, handler })`. A handler named there is followed
# to its definition, so its params and callees land on the route.
expected_endpoints = [
  Endpoint.new("/orders/:orderId", "GET", [Param.new("orderId", "", "path"), Param.new("expand", "", "query")]),
  Endpoint.new("/orders", "POST", [Param.new("sku", "", "json"), Param.new("quantity", "", "json")]),
  Endpoint.new("/orders/:orderId", "DELETE", [Param.new("orderId", "", "path")]),
]

tester = FunctionalTester.new("fixtures/javascript/fastify_route_handler_ref/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

describe "Fastify handlers declared in the route options", tags: "functional" do
  it "names the handler, reads its definition and lets reach find the controller file" do
    endpoints = tester.app.endpoints
    handler_of = ->(method : String, url : String) do
      endpoints.find! { |ep| ep.method == method && ep.url == url }.handler.try { |h| {h.name, File.basename(h.path.to_s), h.line} }
    end

    handler_of.call("GET", "/orders/:orderId").should eq({"orders.show", "orders.js", 3})
    handler_of.call("POST", "/orders").should eq({"orders.create", "orders.js", 8})
    handler_of.call("DELETE", "/orders/:orderId").should eq({"closure", "server.js", 19})

    show = endpoints.find! { |ep| ep.method == "GET" }
    show.callees.map(&.name).should contain("orderService.find")

    reached = Noir::CLI::Inspect.reach(endpoints, "controllers/orders.js", nil, false)
    reached.map { |row| "#{row.method} #{row.url}" }.sort!.should eq(["GET /orders/:orderId", "POST /orders"])
    reached.flat_map(&.via.map(&.kind)).should contain("handler")
  end
end
