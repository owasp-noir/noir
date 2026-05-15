require "../../func_spec.cr"

post_index = Endpoint.new("/post/index", "GET", [
  Param.new("page", "", "query"),
  Param.new("limit", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("Yii::$app->request->get", line: 13))
  ep.push_callee(Callee.new("$this->render", line: 15))
end

post_view = Endpoint.new("/post/view", "GET", [
  Param.new("id", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("$this->render", line: 20))
end

post_create_callees = [
  Callee.new("Yii::$app->request->post", line: 25),
  Callee.new("Yii::$app->request->headers->get", line: 27),
  Callee.new("$this->render", line: 28),
]

post_create_post = Endpoint.new("/post/create", "POST", [
  Param.new("title", "", "form"),
  Param.new("body", "", "form"),
  Param.new("X-CSRF-Token", "", "header"),
]).tap do |ep|
  post_create_callees.each { |callee| ep.push_callee(callee) }
end

post_create_get = Endpoint.new("/post/create", "GET", [
  Param.new("title", "", "form"),
  Param.new("body", "", "form"),
]).tap do |ep|
  post_create_callees.each { |callee| ep.push_callee(callee) }
end

user_profile = Endpoint.new("/user/profile", "GET", [
  Param.new("id", "", "query"),
  Param.new("session_id", "", "cookie"),
  Param.new("Authorization", "", "header"),
]).tap do |ep|
  ep.push_callee(Callee.new("Yii::$app->request->cookies->get", line: 14))
  ep.push_callee(Callee.new("Yii::$app->request->headers->get", line: 15))
end

user_search = Endpoint.new("/user/search", "GET", [
  Param.new("q", "", "query"),
  Param.new("tag", "", "query"),
]).tap do |ep|
  ep.push_callee(Callee.new("$request->get", line: 22))
end

expected_endpoints = [
  post_index,
  post_view,
  post_create_post,
  post_create_get,
  user_profile,
  user_search,
]

FunctionalTester.new("fixtures/php/yii/", {
  :techs     => 2,
  :endpoints => 20,
}, expected_endpoints, {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

describe "Yii config route callees" do
  it "keeps urlManager-only routes callee-empty" do
    config_init = ConfigInitializer.new
    noir_options = config_init.default_options
    noir_options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/php/yii/")])
    noir_options["nolog"] = YAML::Any.new(true)
    noir_options["include_callee"] = YAML::Any.new(true)

    app = NoirRunner.new noir_options
    app.detect
    app.analyze

    endpoint = app.endpoints.find { |e| e.method == "GET" && e.url == "/health" }
    endpoint.should_not be_nil
    endpoint.callees.should be_empty if endpoint
  end
end
