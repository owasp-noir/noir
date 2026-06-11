require "../../func_spec.cr"

expected_endpoints = [
  Endpoint.new("/custom-trpc/user.list", "GET", [] of Param),
  Endpoint.new("/custom-trpc/user.byId", "GET", [
    Param.new("id", "", "query"),
  ]),
  Endpoint.new("/custom-trpc/user.create", "POST", [
    Param.new("name", "", "body"),
    Param.new("email", "", "body"),
  ]),
  Endpoint.new("/custom-trpc/post.list", "GET", [] of Param),
  Endpoint.new("/custom-trpc/post.byId", "GET", [
    Param.new("postId", "", "query"),
  ]),
  Endpoint.new("/custom-trpc/post.liveFeed", "SUBSCRIBE", [] of Param),
  Endpoint.new("/custom-trpc/account.me", "GET", [] of Param),
  Endpoint.new("/custom-trpc/account.update", "POST", [
    Param.new("displayName", "", "body"),
  ]),
  Endpoint.new("/custom-trpc/health", "GET", [] of Param),
]

FunctionalTester.new("fixtures/typescript/trpc/", {
  :techs     => 1,
  :endpoints => expected_endpoints.size,
}, expected_endpoints).perform_tests

describe "tRPC source filtering" do
  it "skips test route fixtures and route-like docs strings" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/trpc/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    urls = app.endpoints.map(&.url)
    urls.should_not contain("/custom-trpc/debug")
    urls.should_not contain("/custom-trpc/hidden")
  end

  it "attributes nested procedures to their procedure key line" do
    options = ConfigInitializer.new.default_options
    options["base"] = YAML::Any.new([YAML::Any.new("./spec/functional_test/fixtures/typescript/trpc/")])
    options["nolog"] = YAML::Any.new(true)

    app = NoirRunner.new(options)
    app.detect
    app.analyze

    by_id = app.endpoints.find! { |ep| ep.method == "GET" && ep.url == "/custom-trpc/post.byId" }
    by_id.details.code_paths.first.line.should eq(6)

    live_feed = app.endpoints.find! { |ep| ep.method == "SUBSCRIBE" && ep.url == "/custom-trpc/post.liveFeed" }
    live_feed.details.code_paths.first.line.should eq(9)
  end
end
