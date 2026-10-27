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

  it "bounds the action-body check to the action itself" do
    noir_options = create_test_options
    tmpdir = File.tempname("aspnet_action_body")
    Dir.mkdir_p(tmpdir)
    controller = File.join(tmpdir, "ItemsController.cs")
    File.write(controller, [
      "public class ItemsController : ControllerBase",                      # 1
      "{",                                                                  # 2
      "    [HttpGet(\"public\")]",                                          # 3
      "    public IActionResult Public() => Ok(\"x\");",                    # 4
      "",                                                                   # 5
      "    [HttpGet(\"me\")]",                                              # 6
      "    public IActionResult Me()",                                      # 7
      "    {",                                                              # 8
      "        if (!User.Identity.IsAuthenticated) return Unauthorized();", # 9
      "        return Ok(\"me\");",                                         # 10
      "    }",                                                              # 11
      "}",                                                                  # 12
    ].join("\n"))
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {4 => "/public", 7 => "/me"}.map do |line, url|
      details = Details.new(PathInfo.new(controller, line))
      details.technology = "cs_aspnet_core_mvc"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    AspnetAuthTagger.new(noir_options).perform(endpoints)

    endpoints[0].tags.empty?.should be_true
    endpoints[1].tags.map(&.description).should eq(["Protected by ASP.NET User.Identity.IsAuthenticated"])

    FileUtils.rm_rf(tmpdir)
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

    it "reads [Authorize] on the route's own lambda, not the previous statement's" do
      noir_options = create_test_options
      tmpdir = File.tempname("aspnet_minimal_lambda")
      Dir.mkdir_p(tmpdir)
      program = File.join(tmpdir, "Program.cs")
      File.write(program, [
        "var app = builder.Build();",
        "",
        "app.MapGet(\"/secret\", [Authorize] () => \"secret\");",
        "app.MapGet(\"/open\", () => \"open\");",
        "app.Run();",
      ].join("\n"))
      noir_options["base"] = YAML::Any.new(tmpdir)

      secret_details = Details.new(PathInfo.new(program, 3))
      secret_details.technology = "cs_aspnet_core_minimal_api"
      secret = Endpoint.new("/secret", "GET", [] of Param, secret_details)
      open_details = Details.new(PathInfo.new(program, 4))
      open_details.technology = "cs_aspnet_core_minimal_api"
      open = Endpoint.new("/open", "GET", [] of Param, open_details)

      AspnetAuthTagger.new(noir_options).perform([secret, open])

      secret.tags.map(&.description).should eq(["Protected by ASP.NET [Authorize]"])
      open.tags.empty?.should be_true

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

  it "inherits RequireAuthorization chained on a route-builder extension method's call site" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("aspnet_extension_group")
    Dir.mkdir_p(tmpdir)
    program = File.join(tmpdir, "Program.cs")
    orders = File.join(tmpdir, "OrdersApi.cs")
    todos = File.join(tmpdir, "TodosApi.cs")
    File.write(program, <<-CS)
      var app = builder.Build();
      var orders = app.NewVersionedApi("Orders");
      orders.MapOrdersApi()
            .RequireAuthorization();
      app.MapGroup("/todos").RequireAuthorization().MapTodosApi();
      app.MapGroup("/public").MapPublicApi().RequireAuthorization();
      CS
    File.write(orders, <<-CS)
      public static class OrdersApi
      {
          public static RouteGroupBuilder MapOrdersApi(this IEndpointRouteBuilder app)
          {
              var api = app.MapGroup("api/orders").HasApiVersion(1.0);
              api.MapGet("/{id}", GetOrder);
              api.MapGet("/health", () => "ok").AllowAnonymous();
              app.MapGet("/status", () => "up");
              return api;
          }
      }
      CS
    File.write(todos, <<-CS)
      public static class TodosApi
      {
          public static RouteGroupBuilder MapTodosApi(this RouteGroupBuilder group)
          {
              group.MapGet("/", () => "all");
              return group;
          }

          public static RouteGroupBuilder MapPublicApi(this RouteGroupBuilder group)
          {
              var inner = group.MapGroup("/v1");
              inner.MapGet("/", () =>
              {
                  var items = new[] { "a" };
                  return items;
              });
              return group;
          }
      }
      CS
    {program, orders, todos}.each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(path : String, line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(path, line))) }
      order = at.call(orders, 6)
      health = at.call(orders, 7)
      status = at.call(orders, 8)
      todo = at.call(todos, 5)
      public_v1 = at.call(todos, 12)

      AspnetAuthTagger.new(noir_options).perform([order, health, status, todo, public_v1])

      # The call site authorizes the group the extension returns...
      order.tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization() (route group)"])
      # ...unless the route opts out, and not a route mapped straight on `app`.
      health.tags.should be_empty
      status.tags.should be_empty
      # Ahead of the call it covers the `this` group itself.
      todo.tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization() (route group)"])
      # Behind a call returning `group`, a group made from it inherits it too.
      public_v1.tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization() (route group)"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "inherits RequireAuthorization through nested MapGroup declarations" do
    tmpdir = File.tempname("aspnet_nested_group")
    Dir.mkdir_p(tmpdir)
    program = File.join(tmpdir, "Program.cs")
    File.write(program, <<-CS)
      var app = builder.Build();
      var api = app.MapGroup("/api").RequireAuthorization();
      var v1 = api.MapGroup("/v1");
      RouteGroupBuilder admin = v1.MapGroup("/admin");
      v1.MapGet("/items", () => "items");
      admin.MapGet("/stats", () => "stats");
      var pub = app.MapGroup("/public");
      pub.MapGet("/ping", () => "pong");
      CS

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) { Endpoint.new("/#{line}", "GET", [] of Param, Details.new(PathInfo.new(program, line))) }
      items = at.call(5)
      stats = at.call(6)
      ping = at.call(8)

      AspnetAuthTagger.new(noir_options).perform([items, stats, ping])

      items.tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization()"])
      stats.tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization()"])
      ping.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  describe "filter attributes, inherited attributes and in-action refusals" do
    filters_base = File.expand_path("../../../functional_test/fixtures/csharp/aspnet_auth_filters", __DIR__)
    controllers = "#{filters_base}/Controllers/Controllers.cs"
    source = File.read_lines(controllers)
    tags_for = ->(signature : String, after : String) do
      start = source.index!(&.includes?(after))
      line = source.index!(start, &.includes?(signature)) + 1
      details = Details.new(PathInfo.new(controllers, line))
      details.technology = "cs_aspnet_core_mvc"
      endpoint = Endpoint.new("/x", "GET", [] of Param, details)
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(filters_base)
      CodeLocator.instance.clear_all
      Dir.glob("#{filters_base}/**/*.cs").each { |path| CodeLocator.instance.register_path(path) }
      begin
        AspnetAuthTagger.new(noir_options).perform([endpoint])
      ensure
        CodeLocator.instance.clear_all
      end
      endpoint.tags
    end

    it "judges a base class's filter attribute by its definition, noting a permission lookup" do
      tags = tags_for.call("IActionResult Index()", "class ReportsController")
      tags.size.should eq(1)
      tags[0].name.should eq("authz")
      tags[0].description.should contain("[RequireAdmin]")
      tags[0].description.should contain("a setting can admit anonymous callers")
    end

    it "lets an action opt out of a filter with its bool constructor argument" do
      tags_for.call("IActionResult Status()", "class ReportsController").should be_empty
    end

    it "reads [Authorize] inherited from a base controller" do
      tags_for.call("IActionResult Index()", "class SettingsController").map(&.description).should eq(["Protected by ASP.NET [Authorize] (inherited from SecureBase)"])
    end

    it "takes a filter refusing an unauthenticated caller as a hard guard" do
      tags = tags_for.call("IActionResult Profile()", "class AccountController")
      tags.map(&.name).should eq(["auth"])
      tags[0].description.should contain("[SignedIn]")
    end

    it "ignores filters that never refuse and refusals on bad input" do
      tags_for.call("IActionResult Login(", "class AccountController").should be_empty
    end

    it "reads a refusal conditioned on the caller, directly or through a returned helper" do
      tags_for.call("Task<IActionResult> Orders()", "class AccountController").map(&.description).should eq(["Protected by an in-action Challenge when the caller does not qualify"])
      tags_for.call("Task<IActionResult> Quote(", "class AccountController").map(&.description).should eq(["Protected by CheckCallerAsync() (Forbid when the caller does not qualify)"])
    end
  end
end
