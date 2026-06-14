require "../../func_spec.cr"

def get_server_endpoint(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

user_callees = [Callee.new("UserPage", line: 13)]
all_verbs = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]

expected_endpoints = [
  # `name: Routes.HOME` resolves to the `'/'` path constant.
  get_server_endpoint("/", "GET", [] of Param, [Callee.new("HomePage", line: 11)]),
  # Explicit verbs.
  get_server_endpoint("/upload", "POST", [] of Param, [Callee.new("UploadPage", line: 15)]),
  # `Method.ws` surfaces as a GET upgrade.
  get_server_endpoint("/socket", "GET", [] of Param, [Callee.new("SocketPage", line: 17)]),
  # Plain string-literal name.
  get_server_endpoint("/health", "GET", [] of Param, [Callee.new("HealthPage", line: 19)]),
  # `Routes.ITEMS = '$API/items'` resolves the inter-constant
  # interpolation to `/api/items`.
  get_server_endpoint("/api/items", "GET", [] of Param, [Callee.new("ItemsPage", line: 21)]),
]

# `name: Routes.USER` → `/user/:id` → `{id}`; no `method:` defaults to
# `Method.dynamic`, which matches every verb.
all_verbs.each do |verb|
  expected_endpoints << get_server_endpoint("/user/{id}", verb, [Param.new("id", "", "path")], user_callees)
end

tester = FunctionalTester.new("fixtures/dart/get_server/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "resolves GetPage name constants declared in a separate file" do
  tester.app.endpoints.any? { |e| e.url == "/user/{id}" }.should be_true
end

it "skips GetPage entries declared under test/" do
  tester.app.endpoints.any? { |e| e.url == "/test-only" }.should be_false
end
