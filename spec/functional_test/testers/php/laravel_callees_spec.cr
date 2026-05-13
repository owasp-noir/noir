require "../../func_spec.cr"

health = Endpoint.new("/health", "GET").tap do |ep|
  ep.push_callee(Callee.new("HealthCheck::ready", line: 9))
  ep.push_callee(Callee.new("response", line: 10))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("BuildUser::fromRequest", line: 14))
  ep.push_callee(Callee.new("UserService::create", line: 15))
  ep.push_callee(Callee.new("response", line: 16))
end

contact_callees = [
  Callee.new("ContactNotifier::deliver", line: 20),
  Callee.new("view", line: 21),
]

contact_get = Endpoint.new("/contact", "GET").tap do |ep|
  contact_callees.each { |callee| ep.push_callee(callee) }
end

contact_post = Endpoint.new("/contact", "POST").tap do |ep|
  contact_callees.each { |callee| ep.push_callee(callee) }
end

webhook_delete = Endpoint.new("/webhook", "DELETE").tap do |ep|
  ep.push_callee(Callee.new("WebhookHandler::dispatch", line: 25))
  ep.push_callee(Callee.new("response", line: 26))
end

ready = Endpoint.new("/ready", "GET").tap do |ep|
  ep.push_callee(Callee.new("ReadyProbe::check", line: 29))
end

reports = Endpoint.new("/reports", "GET")
photos_index = Endpoint.new("/photos", "GET")

expected_endpoints = [
  health,
  users_create,
  contact_get,
  contact_post,
  webhook_delete,
  ready,
  reports,
  photos_index,
]

tester = FunctionalTester.new("fixtures/php/laravel_callees/", {
  :techs     => 1,
  :endpoints => 21,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
  "only_techs"     => YAML::Any.new("php_laravel"),
})
tester.perform_tests

describe "Laravel callee extraction" do
  it "keeps controller array routes and resource routes callee-empty" do
    reports_endpoint = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/reports" }
    photos_endpoint = tester.app.endpoints.find { |e| e.method == "GET" && e.url == "/photos" }

    reports_endpoint.should_not be_nil
    photos_endpoint.should_not be_nil

    reports_endpoint.callees.should be_empty if reports_endpoint
    photos_endpoint.callees.should be_empty if photos_endpoint
  end
end
