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
end
