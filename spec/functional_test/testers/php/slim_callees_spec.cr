require "../../func_spec.cr"

root = Endpoint.new("/", "GET").tap do |ep|
  ep.push_callee(Callee.new("$response->getBody()->write", line: 11))
end

users_index = Endpoint.new("/users", "GET", [
  Param.new("page", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->getQueryParams", line: 16))
  ep.push_callee(Callee.new("UserService::list", line: 17))
  ep.push_callee(Callee.new("AuditLog::write", line: 18))
  ep.push_callee(Callee.new("$response->getBody()->write", line: 19))
  ep.push_callee(Callee.new("json_encode", line: 19))
end

users_create = Endpoint.new("/users", "POST").tap do |ep|
  ep.push_callee(Callee.new("BuildUser::fromArray", line: 24))
  ep.push_callee(Callee.new("$request->getParsedBody", line: 24))
  ep.push_callee(Callee.new("UserService::create", line: 25))
  ep.push_callee(Callee.new("JsonResponder::created", line: 26))
end

login_get = Endpoint.new("/login", "GET", [
  Param.new("session", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->getCookieParams", line: 30))
  ep.push_callee(Callee.new("AuthService::login", line: 31))
end

login_post = Endpoint.new("/login", "POST", [
  Param.new("session", "", "cookie"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->getCookieParams", line: 30))
  ep.push_callee(Callee.new("AuthService::login", line: 31))
end

item_show = Endpoint.new("/api/items/{itemId}", "GET", [
  Param.new("itemId", "", "path"),
]).tap do |ep|
  ep.push_callee(Callee.new("ItemService::find", line: 37))
  ep.push_callee(Callee.new("JsonResponder::ok", line: 38))
end

expected_endpoints = [
  root,
  users_index,
  users_create,
  login_get,
  login_post,
  item_show,
]

FunctionalTester.new("fixtures/php/slim_callees/", {
  :techs     => 2,
  :endpoints => 6,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests
