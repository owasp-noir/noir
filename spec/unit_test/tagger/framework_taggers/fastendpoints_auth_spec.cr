require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "FastEndpointsAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/csharp/fastendpoints"
  create_user_path = "#{fixture_base}/Endpoints/CreateUserEndpoint.cs"
  ping_path = "#{fixture_base}/Endpoints/PingEndpoint.cs"

  it "detects Roles protection on actions" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(create_user_path, 8))
    details.technology = "cs_fastendpoints"
    endpoint = Endpoint.new("/users", "POST", [] of Param, details)

    tagger = FastEndpointsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("fastendpoints_auth")
    endpoint.tags[0].description.should contain("Roles")
  end

  it "respects AllowAnonymous" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(ping_path, 7))
    details.technology = "cs_fastendpoints"
    endpoint = Endpoint.new("/ping", "GET", [] of Param, details)

    tagger = FastEndpointsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end
end
