require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "AspnetAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/csharp/aspnet_auth", __DIR__)
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

  it "applies FallbackPolicy and MapGroup auth, honouring [AllowAnonymous] in attribute lists and on controllers" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("aspnet_fallback")
    Dir.mkdir_p(tmpdir)
    program = File.join(tmpdir, "Program.cs")
    controllers = File.join(tmpdir, "Controllers.cs")
    File.write(program, <<-CS)
      builder.Services.AddAuthorization(options =>
      {
          options.FallbackPolicy = new AuthorizationPolicyBuilder()
              .RequireAuthenticatedUser()
              .Build();
      });
      var app = builder.Build();
      var api = app.MapGroup("/api").RequireAuthorization("admin");
      api.MapGet("/stats", () => "stats");
      app.MapGet("/ping", () => "pong").AllowAnonymous();
      app.MapGet("/me", () => "me");
      CS
    File.write(controllers, <<-CS)
      public class AccountController : ControllerBase
      {
          [HttpPost("login"), AllowAnonymous]
          public IActionResult Login() => Ok();
      }

      [AllowAnonymous]
      public class PublicController : ControllerBase
      {
          [HttpGet("info")]
          public IActionResult Info() => Ok();
      }
      CS
    CodeLocator.instance.register_path(program)
    CodeLocator.instance.register_path(controllers)

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(path : String, line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(path, line))) }
      stats = at.call(program, 9)
      ping = at.call(program, 10)
      me = at.call(program, 11)
      login = at.call(controllers, 4)
      info = at.call(controllers, 11)

      AspnetAuthTagger.new(noir_options).perform([stats, ping, me, login, info])

      stats.tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization()"])
      ping.tags.should be_empty
      me.tags.map(&.description).should eq(["Protected by ASP.NET FallbackPolicy (RequireAuthenticatedUser)"])
      login.tags.should be_empty
      info.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads app-wide auth only from live, non-test code of the endpoint's own project" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("aspnet_global_scope")
    files = {
      "Web/Web.csproj" => "<Project />",
      "Web/Program.cs" => <<-CS,
        // options.FallbackPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build();
        /* builder.Services.AddControllers(o => o.Filters.Add(new AuthorizeFilter())); */
        var app = builder.Build();
        CS
      "Web/Controllers/Home.cs" => <<-CS,
        public class HomeController : Controller
        {
            [HttpGet("home")]
            public IActionResult Index() => Ok();
        }
        CS
      "Web.Tests/Web.Tests.csproj" => "<Project />",
      "Web.Tests/AuthFactory.cs"   => <<-CS,
        public class AuthFactory : WebApplicationFactory<Program>
        {
            void Configure(IServiceCollection services) =>
                services.AddAuthorization(o => o.FallbackPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());
        }
        CS
      "Admin/Admin.csproj" => "<Project />",
      "Admin/Program.cs"   => <<-CS,
        builder.Services.AddAuthorization(o => o.FallbackPolicy = new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build());
        CS
      "Admin/Controllers/Dashboard.cs" => <<-CS,
        public class DashboardController : Controller
        {
            [HttpGet("dash")]
            public IActionResult Index() => Ok();
        }
        CS
    }
    files.each do |rel, body|
      path = File.join(tmpdir, rel)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      home = Endpoint.new("/home", "GET", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, "Web/Controllers/Home.cs"), 4)))
      home.details.technology = "cs_aspnet_core_mvc"
      dash = Endpoint.new("/dash", "GET", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, "Admin/Controllers/Dashboard.cs"), 4)))
      dash.details.technology = "cs_aspnet_core_mvc"

      AspnetAuthTagger.new(noir_options).perform([home, dash])

      home.tags.should be_empty
      dash.tags.map(&.description).should eq(["Protected by ASP.NET FallbackPolicy (RequireAuthenticatedUser)"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end
end
