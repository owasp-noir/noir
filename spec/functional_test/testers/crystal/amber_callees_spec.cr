require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("HomeService.build", line: 5))
  ep.push_callee(Callee.new("json", line: 5))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("params.json", line: 9))
  ep.push_callee(Callee.new("UserService.create", line: 10))
  ep.push_callee(Callee.new("AuditTrail.record", line: 11))
end

post_show = Endpoint.new("/posts/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("PostLookup.find", line: 16))
  ep.push_callee(Callee.new("render_post", line: 17))
end

upload = Endpoint.new("/upload", "POST").tap do |ep|
  ep.push_callee(Callee.new("params.body", line: 21))
  ep.push_callee(Callee.new("UploadService.store", line: 22))
  ep.push_callee(Callee.new("context.request.headers", line: 23))
end

socket = Endpoint.new("/socket", "GET").tap do |ep|
  ep.push_callee(Callee.new("SocketTracker.connected", line: 29))
  ep.push_callee(Callee.new("socket.send", line: 30))
end

health = Endpoint.new("/health", "GET")

expected_endpoints = [
  home,
  users_create,
  post_show,
  upload,
  socket,
  health,
]

tester = FunctionalTester.new("fixtures/crystal/amber_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("crystal_amber"),
})
tester.perform_tests

describe "Amber callee extraction" do
  it "keeps controller-less fallback routes callee-empty" do
    health_endpoint = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/health" }
    health_endpoint.should_not be_nil
    health_endpoint.callees.should be_empty if health_endpoint
  end
end
