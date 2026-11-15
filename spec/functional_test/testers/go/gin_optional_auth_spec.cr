require "../../func_spec.cr"

describe "Go caller-dependent guards", tags: "functional" do
  it "leaves optional auth and feature gates open beside real guards" do
    tester = FunctionalTester.new("fixtures/go/gin_optional_auth/", nil, nil, {
      "use_taggers" => YAML::Any.new("go_auth,go_security"),
      "ai_context"  => YAML::Any.new(true),
    })
    endpoints = tester.endpoints
    endpoints.size.should eq(7)
    %w[/optional /mcp/message /group/public].each do |url|
      endpoint = endpoints.find!(&.url.==(url))
      endpoint.tags.select(&.name.in?("auth", "authz")).should be_empty
      endpoint.resolution.try(&.["guard"]?).should be_nil
      endpoint.ai_context.should_not be_nil
      endpoint.ai_context.not_nil!.guards.should be_empty
    end
    {"/user" => "auth", "/token" => "auth", "/admin" => "authz", "/group/private" => "auth"}.each do |url, kind|
      endpoint = endpoints.find!(&.url.==(url))
      endpoint.tags.map(&.name).should contain(kind)
      endpoint.resolution.try(&.["guard"]?).should be_nil
    end
  end
end
