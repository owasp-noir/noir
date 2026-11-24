require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# The fastendpoints_auth tags of the endpoints `{method, line}` of `file`.
private def fastendpoints_tags(files : Hash(String, String), file : String, method : String, line : Int32) : Array(Tag)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("fastendpoints_requires")
  files.each do |rel, body|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
    CodeLocator.instance.register_path(path)
  end
  begin
    options = create_test_options
    options["base"] = YAML::Any.new(tmpdir)
    details = Details.new(PathInfo.new(File.join(tmpdir, file), line))
    details.technology = "cs_fastendpoints"
    endpoint = Endpoint.new("/x", method, [] of Param, details)
    FastEndpointsAuthTagger.new(options).perform([endpoint])
    endpoint.tags
  ensure
    FileUtils.rm_rf(tmpdir)
    CodeLocator.instance.clear_all
  end
end

private def fe_requires(tags : Array(Tag)) : Array(Array(String))
  tags[0].requires.not_nil!.map(&.any_of.map(&.to_s))
end

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
    endpoint.tags[0].requires.not_nil!.map(&.any_of.map(&.to_s)).should eq([["authenticated"]])
  end

  it "requires a signed-in caller holding one of the roles and one of the permissions" do
    noir_options = create_test_options
    tmpdir = File.tempname("fastendpoints_requires")
    Dir.mkdir_p(tmpdir)
    file = File.join(tmpdir, "ExportEndpoint.cs")
    File.write(file, <<-CS)
      public class ExportEndpoint : EndpointWithoutRequest
      {
          public override void Configure()
          {
              Get("/api/export");
              Roles("Admin", "Manager");
              Permissions(Perms.Export, "reports:read");
          }
      }
      CS
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(file, 5))
    details.technology = "cs_fastendpoints"
    endpoint = Endpoint.new("/api/export", "GET", [] of Param, details)
    FastEndpointsAuthTagger.new(noir_options).perform([endpoint])
    FileUtils.rm_rf(tmpdir)

    endpoint.tags.map(&.description).should eq(["Protected by FastEndpoints Roles"])
    endpoint.tags[0].requires.not_nil!.map(&.any_of.map(&.to_s)).should eq([["authenticated"], ["role:Admin", "role:Manager"], ["permission:reports:read", "unresolved"]])
  end

  it "reads the endpoint's own class, not the file's first Configure" do
    files = {"Two.cs" => <<-CS}
      public class ListOrders : EndpointWithoutRequest
      {
          public override void Configure()
          {
              Get("/orders");
              Roles("User");
          }
      }

      public class DeleteOrder : EndpointWithoutRequest
      {
          public override void Configure()
          {
              Delete("/orders/{id}");
              Roles("Admin");
          }
      }

      [HttpPost("/f01"), Authorize(Roles = "Admin,Manager")]
      public class UpdateAddress : EndpointWithoutRequest
      {
      }
      CS
    delete = fastendpoints_tags(files, "Two.cs", "DELETE", 10)
    delete.map(&.description).should eq(["Protected by FastEndpoints Roles"])
    fe_requires(delete).should eq([["authenticated"], ["role:Admin"]])
    fe_requires(fastendpoints_tags(files, "Two.cs", "POST", 19)).should eq([["role:Admin", "role:Manager"]])
  end

  it "reads AllowAnonymous for the verbs it names and keeps a global configurator unread" do
    files = {
      "Program.cs" => %(app.UseFastEndpoints(c => c.Endpoints.Configurator = ep => ep.Roles("GlobalAdmin"));),
      "Eps.cs"     => <<-CS,
        public class First : EndpointWithoutRequest
        {
            public override void Configure() { Get("/first"); }
        }

        public class Mixed : EndpointWithoutRequest
        {
            public override void Configure()
            {
                Verbs(Http.GET, Http.POST);
                Routes("/mixed");
                AllowAnonymous(Http.GET);
            }
        }
        CS
    }
    fe_requires(fastendpoints_tags(files, "Eps.cs", "GET", 6)).should eq([["anonymous"], ["unresolved"]])
    fe_requires(fastendpoints_tags(files, "Eps.cs", "POST", 6)).should eq([["authenticated"], ["unresolved"]])
  end
end
