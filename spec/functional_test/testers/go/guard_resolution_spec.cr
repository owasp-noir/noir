require "../../func_spec.cr"

describe "Go guard resolution", tags: "functional" do
  it "carries matched group evidence and leaves a followed inline body unmarked" do
    tester = FunctionalTester.new("fixtures/go/gin_auth/", nil, nil, {
      "use_taggers" => YAML::Any.new("go_auth"),
    })
    endpoints = tester.endpoints
    group = endpoints.find! { |endpoint| endpoint.url == "/v1/users/add" }
    group.tags.any?(&.name.==("auth")).should be_true
    group.resolution.should eq({"guard" => "heuristic"})
    endpoints.find! { |endpoint| endpoint.url == "/home" }.resolution.should be_nil
    endpoints.find! { |endpoint| endpoint.url == "/health" }.resolution.should be_nil
  end
end
