require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("PageService::home", line: 9))
  ep.push_callee(Callee.new("$this->renderHome", line: 10))
end

article_view = Endpoint.new("/articles/:id", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("ArticleService::find", line: 9))
  ep.push_callee(Callee.new("$this->jsonArticle", line: 10))
end

article_add = Endpoint.new("/articles", "POST").tap do |ep|
  ep.push_callee(Callee.new("ArticlePayload::fromRequest", line: 15))
  ep.push_callee(Callee.new("ArticleService::create", line: 16))
end

photos_index = Endpoint.new("/Photos", "GET").tap do |ep|
  ep.push_callee(Callee.new("PhotoService::list", line: 9))
  ep.push_callee(Callee.new("$this->jsonList", line: 10))
end

photos_add = Endpoint.new("/Photos", "POST").tap do |ep|
  ep.push_callee(Callee.new("PhotoPayload::fromRequest", line: 15))
  ep.push_callee(Callee.new("PhotoService::create", line: 16))
end

photos_view = Endpoint.new("/Photos/{id}", "GET", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("PhotoService::find", line: 21))
  ep.push_callee(Callee.new("$this->jsonPhoto", line: 22))
end

photos_edit_callees = [
  Callee.new("PhotoPayload::fromRequest", line: 27),
  Callee.new("PhotoService::update", line: 28),
]

photos_edit_put = Endpoint.new("/Photos/{id}", "PUT", [
  Param.new("id", "", "path"),
]).tap do |ep|
  photos_edit_callees.each { |callee| ep.push_callee(callee) }
end

photos_edit_patch = Endpoint.new("/Photos/{id}", "PATCH", [
  Param.new("id", "", "path"),
]).tap do |ep|
  photos_edit_callees.each { |callee| ep.push_callee(callee) }
end

photos_delete = Endpoint.new("/Photos/{id}", "DELETE", [
  Param.new("id", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("PhotoService::delete", line: 33))
  ep.push_callee(Callee.new("$this->emptyResponse", line: 34))
end

legacy = Endpoint.new("/legacy", "GET")
computed = Endpoint.new("/computed", "GET")

expected_endpoints = [
  home,
  article_view,
  article_add,
  photos_index,
  photos_add,
  photos_view,
  photos_edit_put,
  photos_edit_patch,
  photos_delete,
  legacy,
  computed,
]

tester = FunctionalTester.new("fixtures/php/cakephp_callees/", {
  :techs     => 1,
  :endpoints => 11,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("php_cakephp"),
})
tester.perform_tests

describe "CakePHP callee extraction" do
  it "keeps unsupported route targets callee-empty" do
    legacy_endpoint = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/legacy" }
    computed_endpoint = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/computed" }

    legacy_endpoint.should_not be_nil
    computed_endpoint.should_not be_nil

    legacy_endpoint.callees.should be_empty if legacy_endpoint
    computed_endpoint.callees.should be_empty if computed_endpoint
  end
end
