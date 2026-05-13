require "../../func_spec.cr"

index_endpoint = Endpoint.new("/posts", "GET").tap do |ep|
  ep.push_callee(Callee.new("PostQuery.list", line: 3))
  ep.push_callee(Callee.new("AuditLog.write", line: 4))
  ep.push_callee(Callee.new("render", line: 5))
  ep.push_callee(Callee.new("serialize_posts", line: 5))
end

show_endpoint = Endpoint.new("/posts/1", "GET").tap do |ep|
  ep.push_callee(Callee.new("Post.find", line: 9))
  ep.push_callee(Callee.new("render", line: 10))
  ep.push_callee(Callee.new("serialize_post", line: 10))
end

create_endpoint = Endpoint.new("/posts", "POST").tap do |ep|
  ep.push_callee(Callee.new("PostCreator.create", line: 14))
  ep.push_callee(Callee.new("AuditLog.write", line: 15))
  ep.push_callee(Callee.new("render", line: 16))
  ep.push_callee(Callee.new("serialize_post", line: 16))
end

preview_endpoint = Endpoint.new("/posts/preview", "GET").tap do |ep|
  ep.push_callee(Callee.new("PreviewBuilder.build", line: 20))
  ep.push_callee(Callee.new("render", line: 21))
  ep.push_callee(Callee.new("serialize_preview", line: 21))
end

status_endpoint = Endpoint.new("/status", "GET").tap do |ep|
  ep.push_callee(Callee.new("Health.check", line: 3))
  ep.push_callee(Callee.new("render", line: 4))
  ep.push_callee(Callee.new("status_payload", line: 4))
end

ping_endpoint = Endpoint.new("/ping", "GET").tap do |ep|
  ep.push_callee(Callee.new("render", line: 7))
  ep.push_callee(Callee.new("Health.check", line: 7))
end

ready_endpoint = Endpoint.new("/ready", "GET").tap do |ep|
  ep.push_callee(Callee.new("render", line: 10))
  ep.push_callee(Callee.new("Ready.check", line: 10))
end

expected_endpoints = [
  index_endpoint,
  show_endpoint,
  create_endpoint,
  preview_endpoint,
  status_endpoint,
  ping_endpoint,
  ready_endpoint,
]

FunctionalTester.new("fixtures/ruby/rails_callees/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
