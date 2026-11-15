require "../../func_spec.cr"

describe "Express guard resolution", tags: "functional" do
  it "carries name and library matches through the runner and leaves public routes unmarked" do
    tester = FunctionalTester.new("fixtures/javascript/express_auth/", nil, nil, {
      "use_taggers" => YAML::Any.new("express_auth"),
    })
    tester.endpoints.each do |endpoint|
      guarded = endpoint.tags.any?(&.name.in?("auth", "authz"))
      endpoint.resolution.should eq(guarded ? {"guard" => "heuristic"} : nil)
    end
    tester.endpoints.count(&.resolution).should eq(11)
  end
  it "leaves a direct refusal followed and marks the same middleware propagated by all()" do
    tester = FunctionalTester.new("fixtures/javascript/express_all_middleware/", nil, nil, {
      "use_taggers" => YAML::Any.new("express_auth"),
    })
    direct = tester.endpoints.find! { |endpoint| endpoint.url == "/api/posts" }
    direct.tags.map(&.name).should eq(["auth"])
    direct.resolution.should be_nil
    scoped = tester.endpoints.reject { |endpoint| endpoint.url == "/api/posts" }
    scoped.size.should eq(2)
    scoped.each do |endpoint|
      endpoint.tags.map(&.name).should eq(["auth"])
      endpoint.resolution.should eq({"guard" => "heuristic"})
    end
  end
end
