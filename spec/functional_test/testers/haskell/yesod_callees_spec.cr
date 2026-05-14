require "../../func_spec.cr"

def yesod_endpoint_with_callees(url, method, params = [] of Param, callees = [] of Callee)
  endpoint = Endpoint.new(url, method, params)
  callees.each { |callee| endpoint.push_callee(callee) }
  endpoint
end

home_callees = [
  Callee.new("loadUsers", line: 8),
  Callee.new("defaultLayout", line: 9),
  Callee.new("setTitle", line: 10),
  Callee.new("toWidget", line: 11),
  Callee.new("renderHome", line: 15),
]

blog_get_callees = [
  Callee.new("Blog.Service.fetch", line: 19),
  Callee.new("returnJson", line: 20),
]

blog_post_callees = [
  Callee.new("requireCheckJsonBody", line: 24),
  Callee.new("savePost", line: 25),
  Callee.new("sendResponseStatus", line: 26),
]

health_callees = [
  Callee.new("healthService", line: 38),
  Callee.new("returnJson", line: 39),
]

faq_callees = [
  Callee.new("loadFaq", line: 31),
  Callee.new("returnJson", line: 33),
  Callee.new("notFound", line: 34),
]

expected_endpoints = [
  yesod_endpoint_with_callees("/", "GET", [] of Param, home_callees),
  yesod_endpoint_with_callees("/blog/:text", "GET", [
    Param.new("text", "Text", "path"),
  ], blog_get_callees),
  yesod_endpoint_with_callees("/blog/:text", "POST", [
    Param.new("text", "Text", "path"),
  ], blog_post_callees),
  yesod_endpoint_with_callees("/faq", "GET", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/faq", "POST", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/faq", "PUT", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/faq", "DELETE", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/faq", "PATCH", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/faq", "OPTIONS", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/faq", "HEAD", [] of Param, faq_callees),
  yesod_endpoint_with_callees("/api/health", "GET", [] of Param, health_callees),
]

tester = FunctionalTester.new("fixtures/haskell/yesod_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
})
tester.perform_tests

it "reports exact Yesod callees by handler convention" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(home_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "uses handle-prefixed Yesod handlers for methodless routes" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/faq" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map { |callee| {callee.name, callee.line} }.should eq(faq_callees.map { |callee| {callee.name, callee.line} })
  end
end

it "does not attach unrelated top-level functions to Yesod endpoints" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/api/health" && found.method == "GET" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    actual.callees.map(&.name).should_not contain("hiddenCall")
  end
end

it "populates Yesod callee source paths" do
  endpoint = tester.app.endpoints.find { |found| found.url == "/blog/:text" && found.method == "POST" }
  endpoint.should_not be_nil
  endpoint.try do |actual|
    paths = actual.callees.map(&.path)
    paths.uniq!
    paths.should eq([
      "./spec/functional_test/fixtures/haskell/yesod_callees/src/Handler/Home.hs",
    ])
  end
end
