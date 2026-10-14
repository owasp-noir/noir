require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "FastEndpointsAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/csharp/fastendpoints", __DIR__)
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

  it "tags an endpoint without AllowAnonymous as secure by default" do
    noir_options = create_test_options
    tmpdir = File.tempname("fastendpoints_default")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "MyEndpoint.cs")
    File.write(file, [
      "public class MyEndpoint : EndpointWithoutRequest",
      "{",
      "    public override void Configure()",
      "    {",
      "        Get(\"/api/user/profile\");",
      "    }",
      "}",
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(file, 5))
    details.technology = "cs_fastendpoints"
    endpoint = Endpoint.new("/api/user/profile", "GET", [] of Param, details)
    FastEndpointsAuthTagger.new(noir_options).perform([endpoint])
    FileUtils.rm_rf(tmpdir)

    endpoint.tags.map(&.description).should eq(["Protected by FastEndpoints default authorization (no AllowAnonymous)"])
  end
end
