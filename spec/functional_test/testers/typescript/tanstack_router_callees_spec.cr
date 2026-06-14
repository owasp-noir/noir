require "../../func_spec.cr"

posts = Endpoint.new("/posts", "GET")
posts.push_callee(Callee.new("PostsComponent"))

shop = Endpoint.new("/shop", "GET")
shop.push_callee(Callee.new("ShopComponent"))

docs = Endpoint.new("/docs", "GET")
docs.push_callee(Callee.new("DocsRootComponent"))

FunctionalTester.new("fixtures/typescript/tanstack_router/", {
  :techs     => 1,
  :endpoints => 14,
}, [posts, shop, docs], {
  "include_callee" => YAML::Any.new(true),
}).perform_tests

it "does not attach callees from unrelated objects after empty file routes" do
  config_init = ConfigInitializer.new
  noir_options = config_init.default_options
  noir_options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/tanstack_router/")])
  noir_options["nolog"] = YAML::Any.new(true)
  noir_options["include_callee"] = YAML::Any.new(true)

  app = NoirRunner.new(noir_options)
  app.detect
  app.analyze

  empty = app.endpoints.find { |endpoint| endpoint.method == "GET" && endpoint.url == "/empty" }
  empty.should_not be_nil
  if empty
    empty.callees.map(&.name).includes?("Secret.run").should be_false
  end
end
