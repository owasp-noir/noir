require "../../func_spec.cr"

index = Endpoint.new("/", "GET")
index.push_callee(Callee.new("Ok"))

protected_endpoint = Endpoint.new("/api/protected", "GET")
protected_endpoint.push_callee(Callee.new("request.headers.get"))
protected_endpoint.push_callee(Callee.new("request.cookies.get"))
protected_endpoint.push_callee(Callee.new("Ok"))

post_data = Endpoint.new("/api/data", "POST")
post_data.push_callee(Callee.new("request.headers.get"))
post_data.push_callee(Callee.new("Json.toJson"))

FunctionalTester.new("fixtures/scala/play/", {
  :techs     => 1,
  :endpoints => 22,
}, [index, protected_endpoint, post_data], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
