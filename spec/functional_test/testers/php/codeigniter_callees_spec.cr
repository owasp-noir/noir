require "../../func_spec.cr"

home = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("WelcomeService::build", line: 9))
  ep.push_callee(Callee.new("view", line: 10))
end

array_home = Endpoint.new("/array-home", "GET").tap do |ep|
  ep.push_callee(Callee.new("ArrayHomeService::build", line: 15))
  ep.push_callee(Callee.new("view", line: 16))
end

user_show = Endpoint.new("/users/{num}", "GET", [
  Param.new("num", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("UserRepository::find", line: 9))
  ep.push_callee(Callee.new("$this->response->setJSON", line: 10))
end

contact_callees = [
  Callee.new("ContactNotifier::deliver", line: 9),
  Callee.new("view", line: 10),
]

contact_get = Endpoint.new("/contact", "GET").tap do |ep|
  contact_callees.each { |callee| ep.push_callee(callee) }
end

contact_post = Endpoint.new("/contact", "POST").tap do |ep|
  contact_callees.each { |callee| ep.push_callee(callee) }
end

webhook_delete = Endpoint.new("/webhook", "DELETE").tap do |ep|
  ep.push_callee(Callee.new("WebhookHandler::dispatch", line: 9))
  ep.push_callee(Callee.new("$this->response->setJSON", line: 10))
end

photos_index = Endpoint.new("/photos", "GET")

api_status = Endpoint.new("/api/status", "GET").tap do |ep|
  ep.push_callee(Callee.new("StatusProbe::check", line: 11))
  ep.push_callee(Callee.new("$this->response->setJSON", line: 12))
end

expected_endpoints = [
  home,
  array_home,
  user_show,
  contact_get,
  contact_post,
  webhook_delete,
  photos_index,
  api_status,
]

tester = FunctionalTester.new("fixtures/php/codeigniter_callees/", {
  :techs     => 1,
  :endpoints => 21,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("php_codeigniter"),
})
tester.perform_tests

describe "CodeIgniter callee extraction" do
  it "keeps resource convention routes callee-empty in the first pass" do
    photos = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/photos" }
    photos.should_not be_nil
    photos.callees.should be_empty if photos
  end
end
