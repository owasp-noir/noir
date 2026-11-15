require "../../func_spec.cr"

describe "Go guard resolution", tags: "functional" do
  it "follows group Use and keeps an unread credential predicate matched" do
    tester = FunctionalTester.new("fixtures/go/gin_auth/", nil, nil, {
      "use_taggers" => YAML::Any.new("go_auth"),
    })
    endpoints = tester.endpoints
    group = endpoints.find! { |endpoint| endpoint.url == "/v1/users/add" }
    group.tags.any?(&.name.==("auth")).should be_true
    group.resolution.should eq({"guard" => "heuristic"})
    endpoints.find! { |endpoint| endpoint.url == "/api/profile" }.resolution.should be_nil
    endpoints.find! { |endpoint| endpoint.url == "/home" }.resolution.should be_nil
    endpoints.find! { |endpoint| endpoint.url == "/health" }.resolution.should be_nil
  end
  it "follows Gitea's synchronous groups and keeps unknown bodies matched" do
    tester = FunctionalTester.new("fixtures/go/gitea_guard_scope/", nil, nil, {
      "use_taggers" => YAML::Any.new("go_auth"),
    })
    endpoints = tester.endpoints
    %w[/secure/items /secure/nested/items].each do |url|
      endpoint = endpoints.find! { |row| row.url == url }
      endpoint.tags.any?(&.name.==("auth")).should be_true
      endpoint.resolution.try(&.["guard"]?).should be_nil
    end
    matched = endpoints.find! { |row| row.url == "/matched/items" }
    matched.tags.any?(&.name.==("auth")).should be_true
    matched.resolution.try(&.["guard"]?).should eq("heuristic")
    endpoints.find! { |row| row.url == "/public" }.tags.should be_empty
  end
end
