require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "AspnetAuthTagger" do
  fixture_base = "#{__DIR__}/../../../functional_test/fixtures/csharp/aspnet_auth"
  controller_path = "#{fixture_base}/Controllers/PostsController.cs"

  # PostsController.cs line reference:
  #  6: [Authorize]
  #  7: [ApiController]
  #  8: [Route("api/[controller]")]
  #  9: public class PostsController : ControllerBase
  # 11:     [AllowAnonymous]
  # 12:     [HttpGet]
  # 13:     public IActionResult Index()
  # 18:     [HttpGet("{id}")]
  # 19:     public IActionResult Show(int id)
  # 24:     [Authorize(Roles = "Admin")]
  # 25:     [HttpPost]
  # 26:     public IActionResult Create()

  it "detects class-level [Authorize] on actions" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 19))
    details.technology = "cs_aspnet_core_mvc"
    endpoint = Endpoint.new("/api/posts/1", "GET", [] of Param, details)

    tagger = AspnetAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("aspnet_auth")
    endpoint.tags[0].description.should contain("[Authorize]")
  end

  it "respects [AllowAnonymous]" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 13))
    details.technology = "cs_aspnet_core_mvc"
    endpoint = Endpoint.new("/api/posts", "GET", [] of Param, details)

    tagger = AspnetAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects method-level [Authorize(Roles)]" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 26))
    details.technology = "cs_aspnet_core_mvc"
    endpoint = Endpoint.new("/api/posts", "POST", [] of Param, details)

    tagger = AspnetAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].description.should contain("Roles")
  end

  describe "Minimal API fluent .RequireAuthorization()" do
    it "detects .RequireAuthorization() chained on the route statement" do
      noir_options = create_test_options
      tmpdir = File.tempname("aspnet_minimal")
      Dir.mkdir_p(tmpdir)
      program = File.join(tmpdir, "Program.cs")
      File.write(program, [
        "var app = builder.Build();",
        "app.MapGet(\"/secret\", () => \"hi\")",
        "   .RequireAuthorization();",
        "app.MapGet(\"/open\", () => \"hi\");",
        "app.Run();",
      ].join("\n"))
      noir_options["base"] = YAML::Any.new(tmpdir)

      details = Details.new(PathInfo.new(program, 2))
      details.technology = "cs_aspnet_core_minimal_api"
      endpoint = Endpoint.new("/secret", "GET", [] of Param, details)

      tagger = AspnetAuthTagger.new(noir_options)
      tagger.perform([endpoint])

      endpoint.tags.empty?.should be_false
      endpoint.tags[0].description.should contain("RequireAuthorization")

      FileUtils.rm_rf(tmpdir)
    end

    it "does not tag a route whose chain opts out via .AllowAnonymous()" do
      noir_options = create_test_options
      tmpdir = File.tempname("aspnet_minimal_anon")
      Dir.mkdir_p(tmpdir)
      program = File.join(tmpdir, "Program.cs")
      File.write(program, [
        "var app = builder.Build();",
        "app.MapGet(\"/open\", () => \"hi\").AllowAnonymous();",
        "app.Run();",
      ].join("\n"))
      noir_options["base"] = YAML::Any.new(tmpdir)

      details = Details.new(PathInfo.new(program, 2))
      details.technology = "cs_aspnet_core_minimal_api"
      endpoint = Endpoint.new("/open", "GET", [] of Param, details)

      tagger = AspnetAuthTagger.new(noir_options)
      tagger.perform([endpoint])

      endpoint.tags.empty?.should be_true

      FileUtils.rm_rf(tmpdir)
    end
  end
end
