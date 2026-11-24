require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# The aspnet_auth tags of the endpoint at `line` of `file`, scanning `files`.
private def aspnet_tags(files : Hash(String, String), file : String, line : Int32, technology = "cs_aspnet_core_mvc") : Array(Tag)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("aspnet_requires")
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
    details.technology = technology
    endpoint = Endpoint.new("/x", "GET", [] of Param, details)
    AspnetAuthTagger.new(options).perform([endpoint])
    endpoint.tags
  ensure
    FileUtils.rm_rf(tmpdir)
    CodeLocator.instance.clear_all
  end
end

private def requires_of(tag : Tag) : Array(Array(String))
  tag.requires.not_nil!.map(&.any_of.map(&.to_s))
end

private def unread_of(tag : Tag) : Array(String)
  tag.requires.not_nil!.flat_map(&.any_of).select(&.kind.unresolved?).compact_map(&.value)
end

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

  it "takes a caller check as a guard only when the action refuses somewhere" do
    noir_options = create_test_options
    tmpdir = File.tempname("aspnet_reads_caller")
    Dir.mkdir_p(tmpdir)
    controller = File.join(tmpdir, "AccountController.cs")
    program = File.join(tmpdir, "Program.cs")
    File.write(controller, <<-CS)
      public class AccountController : Controller
      {
          public IActionResult Splash()
          {
              var isAdmin = User.IsInRole("Administrator");
              if (!_options.Enabled && !isAdmin) return NotFound();
              return Ok("splash");
          }

          public IActionResult Greeting()
          {
              var name = HttpContext.User.Identity?.Name ?? "guest";
              ViewBag.SignedIn = User.Identity.IsAuthenticated;
              return Ok(name);
          }

          public IActionResult Profile()
          {
              if (!User.Identity.IsAuthenticated) return RedirectToAction("Login");
              return View();
          }

          public IActionResult Settings()
          {
              if (!User.Identity.IsAuthenticated) throw new UnauthorizedAccessException();
              return View();
          }

          public IActionResult Either()
          {
              if (User.Identity.IsAuthenticated) { return Ok(); } else { return Unauthorized(); }
          }

          public IActionResult Ternary()
          {
              return User.Identity.IsAuthenticated ? Ok() : Unauthorized();
          }

          public IActionResult After()
          {
              if (User.Identity.IsAuthenticated) return Ok();
              return Unauthorized();
          }
      }
      CS
    File.write(program, <<-CS)
      app.MapGet("/m1", (HttpContext ctx) =>
      {
          if (!ctx.User.Identity.IsAuthenticated) return Results.Unauthorized();
          return Results.Ok();
      });
      CS
    noir_options["base"] = YAML::Any.new(tmpdir)

    endpoints = {splash: 3, greeting: 10, profile: 17, settings: 23, either: 29, ternary: 34, after: 39}.to_h.transform_values do |line|
      details = Details.new(PathInfo.new(controller, line))
      details.technology = "cs_aspnet_core_mvc"
      Endpoint.new("/#{line}", "GET", [] of Param, details)
    end
    minimal = Details.new(PathInfo.new(program, 1))
    minimal.technology = "cs_aspnet_core_minimal_api"
    endpoints[:minimal] = Endpoint.new("/m1", "GET", [] of Param, minimal)
    AspnetAuthTagger.new(noir_options).perform(endpoints.values)

    endpoints.reject { |_, endpoint| endpoint.tags.any?(&.name.== "auth") }.keys.should eq([:splash, :greeting])

    FileUtils.rm_rf(tmpdir)
  end

  it "applies [Authorize] of one part of a partial controller to the actions of its other files" do
    noir_options = create_test_options
    tmpdir = File.tempname("aspnet_partial")
    Dir.mkdir_p(tmpdir)
    main = File.join(tmpdir, "Main.cs")
    other = File.join(tmpdir, "Main.Users.cs")
    elsewhere = File.join(tmpdir, "Elsewhere.cs")
    File.write(main, "namespace App.A\n{\n    [Authorize(Policy = \"Admin\")]\n    public partial class ServerController : Controller\n    {\n    }\n}\n")
    File.write(other, "namespace App.A\n{\n    public partial class ServerController\n    {\n        [HttpGet(\"users\")]\n        public IActionResult Users() => Ok();\n\n        [AllowAnonymous]\n        [HttpGet(\"open\")]\n        public IActionResult Open() => Ok();\n    }\n}\n")
    # same class name in another namespace: not a part of the guarded type
    File.write(elsewhere, "namespace App.B\n{\n    public partial class ServerController : Controller\n    {\n        [HttpGet(\"b\")]\n        public IActionResult B() => Ok();\n    }\n}\n")
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.clear_all
    Dir.glob("#{tmpdir}/*.cs").each { |path| CodeLocator.instance.register_path(path) }

    endpoints = [{other, 6, "/users"}, {other, 10, "/open"}, {elsewhere, 6, "/b"}].map do |path, line, url|
      details = Details.new(PathInfo.new(path, line))
      details.technology = "cs_aspnet_core_mvc"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    begin
      AspnetAuthTagger.new(noir_options).perform(endpoints)
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(tmpdir)
    end

    endpoints[0].tags.map(&.name).should eq(["auth"])
    endpoints[0].tags[0].description.should eq("Protected by ASP.NET [Authorize(Policy)] (class-level)")
    endpoints[1].tags.should be_empty
    endpoints[2].tags.should be_empty
  end

  it "does not merge same-named partial classes across projects, containing types, type parameters or namespaces of one file" do
    noir_options = create_test_options
    tmpdir = File.tempname("aspnet_partial_scope")
    Dir.mkdir_p(File.join(tmpdir, "A"))
    Dir.mkdir_p(File.join(tmpdir, "B"))
    File.write(File.join(tmpdir, "A", "A.csproj"), "<Project/>")
    File.write(File.join(tmpdir, "B", "B.csproj"), "<Project/>")
    guarded = File.join(tmpdir, "A", "Guarded.cs")
    open_b = File.join(tmpdir, "B", "Open.cs")
    multi = File.join(tmpdir, "B", "Multi.cs")
    File.write(guarded, "namespace App\n{\n    [Authorize]\n    public partial class HomeController : Controller\n    {\n    }\n}\n")
    File.write(open_b, "namespace App\n{\n    public partial class HomeController : Controller\n    {\n        [HttpGet(\"b\")]\n        public IActionResult B() => Ok();\n    }\n    public class Outer\n    {\n        [Authorize]\n        public partial class HomeController\n        {\n        }\n    }\n    [Authorize]\n    public partial class HomeController<T> : Controller\n    {\n    }\n}\n")
    File.write(multi, "namespace One\n{\n    [Authorize]\n    public partial class MultiController : Controller\n    {\n    }\n}\nnamespace Two\n{\n    public partial class MultiController : Controller\n    {\n        [HttpGet(\"m\")]\n        public IActionResult M() => Ok();\n    }\n}\n")
    noir_options["base"] = YAML::Any.new(tmpdir)
    CodeLocator.instance.clear_all
    Dir.glob("#{tmpdir}/**/*.cs").each { |path| CodeLocator.instance.register_path(path) }

    endpoints = [{open_b, 6, "/b"}, {multi, 13, "/m"}].map do |path, line, url|
      details = Details.new(PathInfo.new(path, line))
      details.technology = "cs_aspnet_core_mvc"
      Endpoint.new(url, "GET", [] of Param, details)
    end
    begin
      AspnetAuthTagger.new(noir_options).perform(endpoints)
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(tmpdir)
    end

    endpoints.each(&.tags.should(be_empty))
  end

  it "tags a controller split over many partial files in linear time" do
    tag_parts = ->(count : Int32) do
      noir_options = create_test_options
      tmpdir = File.tempname("aspnet_partial_perf")
      Dir.mkdir_p(tmpdir)
      File.write(File.join(tmpdir, "App.csproj"), "<Project/>")
      File.write(File.join(tmpdir, "Big.cs"), "namespace App\n{\n    [Authorize]\n    public partial class BigController : Controller\n    {\n    }\n}\n")
      endpoints = [] of Endpoint
      count.times do |i|
        path = File.join(tmpdir, "Big.P#{i}.cs")
        actions = (0...4).map { |j| "        [HttpGet(\"p#{i}a#{j}\")]\n        public IActionResult A#{j}() => Ok();\n" }.join
        File.write(path, "namespace App\n{\n    public partial class BigController\n    {\n#{actions}    }\n}\n")
        4.times do |j|
          details = Details.new(PathInfo.new(path, 6 + j * 2))
          details.technology = "cs_aspnet_core_mvc"
          endpoints << Endpoint.new("/p#{i}a#{j}", "GET", [] of Param, details)
        end
      end
      noir_options["base"] = YAML::Any.new(tmpdir)
      CodeLocator.instance.clear_all
      Dir.glob("#{tmpdir}/*.cs").each { |path| CodeLocator.instance.register_path(path) }
      begin
        elapsed = Time.measure { AspnetAuthTagger.new(noir_options).perform(endpoints) }
        endpoints.all? { |endpoint| endpoint.tags.map(&.name) == ["auth"] }.should be_true
        elapsed
      ensure
        CodeLocator.instance.clear_all
        FileUtils.rm_rf(tmpdir)
      end
    end

    small = tag_parts.call(150)
    large = tag_parts.call(600)
    large.should be < (small * 6 + 500.milliseconds)
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

  it "reads a helper extension that authorizes the group it returns as RequireAuthorization" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("aspnet_group_helper")
    Dir.mkdir_p(tmpdir)
    wiring = File.join(tmpdir, "ApiEndpoints.cs")
    routes = File.join(tmpdir, "Routes.cs")
    File.write(wiring, <<-CS)
      public static class ApiEndpoints
      {
          public static void MapApi(this IEndpointRouteBuilder endpoints)
          {
              endpoints.MapGroup("/orders").WithApiDefaults().MapOrderEndpoints();
              var admin = endpoints.MapGroup("/orgs/{orgId}/admin").WithAdminDefaults();
              admin.MapGroup("/users").MapUserEndpoints();
              admin.MapGroup("/pub").AllowAnonymous().MapOpenEndpoints();
              endpoints.MapGroup("/public").WithTags("public").MapPublicEndpoints();
          }

          private static RouteGroupBuilder WithApiDefaults(this RouteGroupBuilder group) =>
              group.WithApiDefaults("Application");

          private static RouteGroupBuilder WithApiDefaults(this RouteGroupBuilder group, string policy)
          {
              group.RequireAuthorization(policy);
              group.WithGroupName("internal");
              return group;
          }

          private static RouteGroupBuilder WithAdminDefaults(this RouteGroupBuilder group)
          {
              group.WithApiDefaults("Admin");
              return group;
          }

          public static RouteGroupBuilder MapScopedGroup(this IEndpointRouteBuilder endpoints)
          {
              var group = endpoints.MapGroup("");
              group.RequireAuthorization("Application");
              return group;
          }
      }
      CS
    File.write(routes, <<-CS)
      public static class Routes
      {
          public static RouteGroupBuilder MapOrderEndpoints(this RouteGroupBuilder group)
          {
              group.MapGet("", () => "orders");
              return group;
          }

          public static RouteGroupBuilder MapUserEndpoints(this RouteGroupBuilder group)
          {
              group.MapGet("", () => "users");
              return group;
          }

          public static RouteGroupBuilder MapPublicEndpoints(this RouteGroupBuilder group)
          {
              group.MapGet("", () => "public");
              return group;
          }

          public static RouteGroupBuilder MapBillingEndpoints(this IEndpointRouteBuilder endpoints)
          {
              var group = endpoints.MapScopedGroup();
              group.MapPost("preview", () => "preview");
              return group;
          }

          public static RouteGroupBuilder MapReportEndpoints(this IEndpointRouteBuilder endpoints)
          {
              var group = endpoints.MapGroup("/reports");
              group.MapGet("a", () => "a").RequireAuthorization();
              group.MapGet("b", () => "b");
              return group;
          }

          public static void MapStatus(this IEndpointRouteBuilder endpoints)
          {
              var reports = endpoints.MapReportEndpoints();
              reports.MapGet("c", () => "c");
          }

          public static RouteGroupBuilder MapOpenEndpoints(this RouteGroupBuilder group)
          {
              group.MapGet("", () => "open");
              return group;
          }
      }
      CS
    {wiring, routes}.each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) do
        details = Details.new(PathInfo.new(routes, line))
        details.technology = "cs_aspnet_core_minimal_api"
        Endpoint.new("/#{line}", "GET", [] of Param, details)
      end
      endpoints = {order: 5, user: 11, public: 17, billing: 24, report_b: 32, report_c: 39, open: 44}.to_h.transform_values { |line| at.call(line) }

      AspnetAuthTagger.new(noir_options).perform(endpoints.values)

      guarded = endpoints.select { |_, endpoint| endpoint.tags.any?(&.name.== "auth") }.keys
      guarded.should eq([:order, :user, :billing])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "credits a route-group helper only to its own project and the projects that reference it" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("aspnet_helper_projects")
    files = {
      "ApiA/ApiA.csproj"   => %(<Project Sdk="Microsoft.NET.Sdk.Web"></Project>),
      "ApiB/ApiB.csproj"   => %(<Project Sdk="Microsoft.NET.Sdk.Web"></Project>),
      "ApiA/Extensions.cs" => "public static class RouteExtensions\n{\n    public static RouteGroupBuilder WithApiDefaults(this RouteGroupBuilder group)\n    {\n        group.MapGroup(\"/x\");\n        group.RequireAuthorization();\n        return group;\n    }\n}\n",
      "ApiB/Extensions.cs" => "public static class RouteExtensions\n{\n    public static RouteGroupBuilder WithApiDefaults(this RouteGroupBuilder group)\n    {\n        group.MapGroup(\"/x\");\n        group.WithOpenApi();\n        return group;\n    }\n}\n",
      "ApiA/Program.cs"    => "var api = app.MapGroup(\"/a\").WithApiDefaults();\napi.MapGet(\"/secret\", () => \"x\");\n",
      "ApiB/Program.cs"    => "var api = app.MapGroup(\"/b\").WithApiDefaults();\napi.MapGet(\"/open\", () => \"x\");\n",
    }
    files.each do |name, body|
      path = File.join(tmpdir, name)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, body)
      CodeLocator.instance.register_path(path)
    end

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      endpoints = %w[ApiA ApiB].map do |project|
        details = Details.new(PathInfo.new(File.join(tmpdir, project, "Program.cs"), 2))
        details.technology = "cs_aspnet_core_minimal_api"
        Endpoint.new("/#{project}", "GET", [] of Param, details)
      end

      AspnetAuthTagger.new(noir_options).perform(endpoints)

      endpoints.map(&.tags.map(&.name)).should eq([["auth"], [] of String])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "finds a route-group helper declared alone in a file that maps nothing" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("aspnet_helper_own_file")
    Dir.mkdir_p(tmpdir)
    helper = File.join(tmpdir, "Extensions.cs")
    program = File.join(tmpdir, "Program.cs")
    File.write(helper, "public static class RouteExtensions\n{\n    public static RouteGroupBuilder WithApiDefaults(this RouteGroupBuilder group)\n    {\n        group.RequireAuthorization();\n        return group;\n    }\n}\n")
    File.write(program, "var api = app.MapGroup(\"/a\").WithApiDefaults();\napi.MapGet(\"/secret\", () => \"x\");\n")
    {helper, program}.each { |path| CodeLocator.instance.register_path(path) }

    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      details = Details.new(PathInfo.new(program, 2))
      details.technology = "cs_aspnet_core_minimal_api"
      endpoint = Endpoint.new("/a/secret", "GET", [] of Param, details)

      AspnetAuthTagger.new(noir_options).perform([endpoint])

      endpoint.tags.map(&.name).should eq(["auth"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
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
      tags_for.call("Task<IActionResult> Orders()", "class AccountController").map(&.description).should eq(["Protected by an in-action Challenge when `user == null`"])
      tags_for.call("Task<IActionResult> Quote(", "class AccountController").map(&.description).should eq(["Protected by CheckCallerAsync() (Forbid when `!User.Identity.IsAuthenticated`)"])
      tags_for.call("Task<IActionResult> Invoice(", "class AccountController").map(&.description).should eq(["Protected by an in-action Challenge when `customer.Id != order.CustomerId`"])
    end

    it "does not take a refusal of one identity, an input lookup or a model property as a guard" do
      tags_for.call("IActionResult Named()", "class AccountController").should be_empty
      tags_for.call("Task<IActionResult> Lookup(", "class AccountController").should be_empty
      tags_for.call("IActionResult Token(", "class AccountController").should be_empty
    end

    it "does not take a filter refusing on a header as an auth guard" do
      tags_for.call("IActionResult Ajax()", "class ItemsController").should be_empty
    end

    it "reads a `true` that makes a filter stricter as no opt-out" do
      tags_for.call("IActionResult Strict()", "class ItemsController").map(&.name).should eq(["auth"])
    end

    it "keeps a filter that does not read [AllowAnonymous]" do
      tags_for.call("IActionResult Anon()", "class ItemsController").map(&.description).first.should contain("[RequireLogin]")
    end

    it "resolves a base class in the deriving file's namespace" do
      base = File.expand_path("../../../functional_test/fixtures/csharp/aspnet_auth_filters", __DIR__)
      users = "#{base}/Admin/UsersController.cs"
      line = File.read_lines(users).index!(&.includes?("IActionResult List()")) + 1
      details = Details.new(PathInfo.new(users, line))
      details.technology = "cs_aspnet_core_mvc"
      endpoint = Endpoint.new("/api/admin/users", "GET", [] of Param, details)
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(base)
      CodeLocator.instance.clear_all
      Dir.glob("#{base}/**/*.cs").each { |path| CodeLocator.instance.register_path(path) }
      begin
        AspnetAuthTagger.new(noir_options).perform([endpoint])
      ensure
        CodeLocator.instance.clear_all
      end
      # The attribute sits on the class: the action's own stack ends at `{`.
      endpoint.tags.map(&.description).should eq(["Protected by ASP.NET [Authorize(Roles)] (class-level)"])
    end
  end

  it "reads [Authorize] on a SignalR hub" do
    tmpdir = File.tempname("aspnet_hub")
    Dir.mkdir_p(tmpdir)
    hub = File.join(tmpdir, "SecureHub.cs")
    File.write(hub, <<-CS)
      [Authorize]
      public class SecureHub : Hub
      {
          public Task Send(string m) => Task.CompletedTask;
      }
      public class OpenHub : Hub
      {
          public Task Send(string m) => Task.CompletedTask;
      }
      CS
    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      at = ->(line : Int32) do
        details = Details.new(PathInfo.new(hub, line))
        details.technology = "cs_signalr"
        Endpoint.new("ws://x", "SEND", [] of Param, details)
      end
      secure = at.call(3)
      open_hub = at.call(8)
      AspnetAuthTagger.new(noir_options).perform([secure, open_hub])
      secure.tags.map(&.name).should eq(["auth"])
      open_hub.tags.should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end

  describe "attributes deriving AuthorizeAttribute / IAllowAnonymous" do
    base = File.expand_path("../../../functional_test/fixtures/csharp/aspnet_core_mvc_const_prefix", __DIR__)
    auth = "#{base}/Controllers/Auth.cs"
    source = File.read_lines(auth)
    tags_for = ->(signature : String) do
      details = Details.new(PathInfo.new(auth, source.index!(&.includes?(signature)) + 1))
      details.technology = "cs_aspnet_core_mvc"
      endpoint = Endpoint.new("/x", "GET", [] of Param, details)
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(base)
      CodeLocator.instance.clear_all
      Dir.glob("#{base}/**/*.cs").each { |path| CodeLocator.instance.register_path(path) }
      begin
        AspnetAuthTagger.new(noir_options).perform([endpoint])
      ensure
        CodeLocator.instance.clear_all
      end
      endpoint.tags
    end

    it "guards an action carrying a custom attribute that derives AuthorizeAttribute" do
      tags = tags_for.call("IActionResult Guarded()")
      tags.map(&.name).should eq(["auth"])
      tags[0].description.should contain("[ApiPermission]")
    end

    it "guards through a class-level derived attribute" do
      tags_for.call("IActionResult Inside()").map(&.name).should eq(["auth"])
    end

    it "keeps the permission check of an IAllowAnonymous attribute as a setting-dependent guard" do
      tags = tags_for.call("IActionResult Open()")
      tags.map(&.name).should eq(["authz"])
      tags[0].description.should contain("[ApiPermissionOrAnonymous]")
    end

    it "lets IAllowAnonymous win over the inherited Authorize when no permission is named" do
      tags_for.call("IActionResult Lifted()").should be_empty
    end

    it "does not take a header-conditioned refusal of an anonymous attribute as a guard" do
      tags_for.call("IActionResult Header()").should be_empty
    end

    it "ignores an attribute that derives neither" do
      tags_for.call("IActionResult Plain()").should be_empty
    end
  end
end

describe "AspnetAuthTagger requires" do
  it "adds every [Authorize] on the action, its class and its base class" do
    files = {"Controllers.cs" => <<-CS}
      [Authorize]
      public abstract class SecureBase : ControllerBase { }

      [Authorize(Policy = "CanExport")]
      public class ReportsController : SecureBase
      {
          [Authorize(Roles = "Admin,Manager")]
          [Authorize(Roles = RoleNames.Auditor)]
          [HttpGet("export")]
          public IActionResult Export() => Ok();
      }
      CS
    tags = aspnet_tags(files, "Controllers.cs", 10)
    tags.map(&.description).should eq(["Protected by ASP.NET [Authorize(Roles)]"])
    requires_of(tags[0]).sort.should eq([["authenticated"], ["role:Admin", "role:Manager"], ["unresolved"], ["unresolved"]])
    unread_of(tags[0]).sort.should eq(["Policy=CanExport", "Roles = RoleNames.Auditor"])
  end

  it "keeps an attribute deriving AuthorizeAttribute next to a plain [Authorize]" do
    files = {"Controllers.cs" => <<-CS}
      public class ApiPermissionAttribute : AuthorizeAttribute
      {
          public ApiPermissionAttribute(string permission) { Policy = permission; }
      }

      [Authorize]
      public class ItemsController : ControllerBase
      {
          [ApiPermission("items.read")]
          [HttpGet("items")]
          public IActionResult List() => Ok();
      }
      CS
    tags = aspnet_tags(files, "Controllers.cs", 11)
    tags.map(&.description).should eq(["Protected by ASP.NET [Authorize] (class-level)"])
    requires_of(tags[0]).should eq([["unresolved"], ["authenticated"]])
    unread_of(tags[0]).should eq([%([ApiPermission("items.read")])])
  end

  it "reads a derived attribute alone as signed in plus unread" do
    files = {"Controllers.cs" => <<-CS}
      public class ApiPermissionAttribute : AuthorizeAttribute { }

      public class ItemsController : ControllerBase
      {
          [ApiPermission]
          [HttpGet("items")]
          public IActionResult List() => Ok();
      }
      CS
    tags = aspnet_tags(files, "Controllers.cs", 7)
    tags.map(&.description).should eq(["Protected by [ApiPermission] (derives AuthorizeAttribute)"])
    requires_of(tags[0]).should eq([["unresolved"], ["authenticated"]])
  end

  it "adds a minimal API route's lambda attribute, its own and its group's RequireAuthorization" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      var api = app.MapGroup("/api").RequireAuthorization("Member");
      api.MapGet("/x", [Authorize(Roles = "Admin")] () => 1).RequireAuthorization(p => p.RequireRole("Ops"));
      app.Run();
      CS
    tags = aspnet_tags(files, "Program.cs", 3, "cs_aspnet_core_minimal_api")
    tags.map(&.description).should eq(["Protected by ASP.NET [Authorize(Roles)]"])
    requires_of(tags[0]).sort.should eq([["authenticated"], ["role:Admin"], ["role:Ops"], ["unresolved"]])
    unread_of(tags[0]).should eq(["Policy=Member"])
  end

  it "adds every RequireAuthorization statement of the route's group" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      var api = app.MapGroup("/api");
      api.RequireAuthorization();
      api.RequireAuthorization("Member");
      api.MapGet("/x", () => 1);
      app.Run();
      CS
    tags = aspnet_tags(files, "Program.cs", 5, "cs_aspnet_core_minimal_api")
    tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization() (route group)"])
    requires_of(tags[0]).sort.should eq([["authenticated"], ["unresolved"]])
  end

  it "reads AllowAnonymous on the route's group as open to anyone" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      var open = app.MapGroup("/open").AllowAnonymous();
      open.MapGet("/x", () => 1).RequireAuthorization();
      app.Run();
      CS
    tags = aspnet_tags(files, "Program.cs", 3, "cs_aspnet_core_minimal_api")
    tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization()"])
    requires_of(tags[0]).should eq([["anonymous"]])
  end

  it "keeps an authorizing helper unread" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      app.MapGet("/x", () => 1).WithApiDefaults();
      app.Run();

      public static class Defaults
      {
          public static RouteHandlerBuilder WithApiDefaults(this RouteGroupBuilder group)
          {
              group.RequireAuthorization("Member");
              return group;
          }
      }
      CS
    tags = aspnet_tags(files, "Program.cs", 2, "cs_aspnet_core_minimal_api")
    tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization()"])
    unread_of(tags[0]).should eq([".WithApiDefaults()"])
    requires_of(tags[0]).should eq([["unresolved"], ["authenticated"]])
  end

  it "reads a bare [Authorize] as signed in plus unread when the code replaces DefaultPolicy" do
    files = {
      "Program.cs"     => %(builder.Services.AddAuthorization(o => o.DefaultPolicy = new AuthorizationPolicyBuilder().RequireClaim("tenant").Build());),
      "Controllers.cs" => <<-CS,
        public class ItemsController : ControllerBase
        {
            [Authorize]
            [HttpGet("items")]
            public IActionResult List() => Ok();
        }
        CS
    }
    tags = aspnet_tags(files, "Controllers.cs", 5)
    requires_of(tags[0]).should eq([["unresolved"], ["authenticated"]])
    unread_of(tags[0]).should eq([%(DefaultPolicy = new AuthorizationPolicyBuilder().RequireClaim("tenant").Build())])
  end

  it "keeps an AuthorizeAttribute the project declares unread" do
    files = {
      "Auth/AuthorizeAttribute.cs" => <<-CS,
        namespace App.Auth;
        public class AuthorizeAttribute : Attribute, IAuthorizationFilter
        {
            public string Roles { get; set; }
            public void OnAuthorization(AuthorizationFilterContext context) { }
        }
        CS
      "Controllers.cs" => <<-CS,
        using App.Auth;
        public class ItemsController : ControllerBase
        {
            [Authorize(Roles = "Admin")]
            [HttpGet("items")]
            public IActionResult List() => Ok();
        }
        CS
    }
    tags = aspnet_tags(files, "Controllers.cs", 6)
    tags.map(&.description).should eq(["Protected by ASP.NET [Authorize(Roles)]"])
    requires_of(tags[0]).should eq([["unresolved"], ["authenticated"]])
    unread_of(tags[0]).should eq([%([Authorize(Roles = "Admin")])])
  end

  it "does not take a later route's AllowAnonymous for a controller action's" do
    files = {"Controllers.cs" => <<-CS}
      public class ItemsController : ControllerBase
      {
          [Authorize]
          [HttpGet("a")]
          public IActionResult A()
          {
              return Ok();
          }

          void Map(IEndpointRouteBuilder app) { app.MapGet("/x", () => 1).AllowAnonymous(); }
      }
      CS
    tags = aspnet_tags(files, "Controllers.cs", 5)
    tags.map(&.description).should eq(["Protected by ASP.NET [Authorize]"])
    requires_of(tags[0]).should eq([["authenticated"]])
  end

  it "does not take a namesake group declared outside the method for the route's" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      var group = app.MapGroup("/public").AllowAnonymous();
      group.MapGet("/a", () => "a");
      app.MapGroup("/admin").MapAdmin();
      app.Run();

      static class AdminRoutes
      {
          public static RouteGroupBuilder MapAdmin(this RouteGroupBuilder group)
          {
              group.MapGet("/users", () => "u").RequireAuthorization();
              return group;
          }
      }
      CS
    tags = aspnet_tags(files, "Program.cs", 11, "cs_aspnet_core_minimal_api")
    tags.map(&.description).should eq(["Protected by ASP.NET .RequireAuthorization()"])
    requires_of(tags[0]).should eq([["authenticated"], ["unresolved"]])
    unread_of(tags[0]).should eq(["the conventions of group, a builder made outside this method"])
  end

  it "keeps a Carter module's conventions unread" do
    files = {"AdminModule.cs" => <<-CS}
      public class AdminModule : CarterModule
      {
          public AdminModule() : base("/admin")
          {
              this.RequireAuthorization("AdminPolicy");
          }

          public override void AddRoutes(IEndpointRouteBuilder app)
          {
              app.MapGet("/stats", () => "s").RequireAuthorization();
          }
      }
      CS
    tags = aspnet_tags(files, "AdminModule.cs", 10, "cs_carter")
    requires_of(tags[0]).should eq([["authenticated"], ["unresolved"]])
  end

  it "adds the layers a route takes from its handler, its metadata and its group's later conventions" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      app.MapGet("/methodgroup", Handlers.Secret).RequireAuthorization();
      app.MapGet("/withmeta", () => "x").RequireAuthorization().WithMetadata(new AuthorizeAttribute { Roles = "M" });
      var late = app.MapGroup("/late");
      late.MapGet("/x", () => "x").RequireAuthorization();
      late.RequireAuthorization("Late");
      app.Run();
      CS
    method_group = aspnet_tags(files, "Program.cs", 2, "cs_aspnet_core_minimal_api")
    requires_of(method_group[0]).should eq([["unresolved"], ["authenticated"]])
    unread_of(method_group[0]).should eq(["attributes of the handler Handlers.Secret"])
    requires_of(aspnet_tags(files, "Program.cs", 3, "cs_aspnet_core_minimal_api")[0]).should eq([["authenticated"], ["role:M"]])
    late = aspnet_tags(files, "Program.cs", 5, "cs_aspnet_core_minimal_api")
    unread_of(late[0]).should eq(["Policy=Late"])
  end

  it "keeps a TypeFilter next to [Authorize] unread" do
    files = {"Controllers.cs" => <<-CS}
      public class CController : ControllerBase
      {
          [Authorize]
          [TypeFilter(typeof(AdminFilter))]
          [HttpGet("typefilter")]
          public IActionResult A() => Ok();
      }
      CS
    tags = aspnet_tags(files, "Controllers.cs", 6)
    requires_of(tags[0]).should eq([["authenticated"], ["unresolved"]])
    unread_of(tags[0]).should eq(["[TypeFilter(typeof(AdminFilter))]"])
  end

  it "reads nothing past the end of a statement that does not compile" do
    files = {"Program.cs" => <<-CS}
      var app = builder.Build();
      app.MapGet("/u", () => "x").RequireAuthorization(p => p.RequireRole("U";
      app.MapGet("/v", () => "x").RequireAuthorization(p => p.RequireRole("V"));
      app.Run();
      CS
    tags = aspnet_tags(files, "Program.cs", 2, "cs_aspnet_core_minimal_api")
    requires_of(tags[0]).should eq([["unresolved"], ["authenticated"]])
  end

  it "reads an in-action refusal a permission setting can lift as unread only" do
    files = {"Controllers.cs" => <<-CS}
      public class ItemsController : Controller
      {
          public async Task<IActionResult> Admin()
          {
              if (!await _permissionService.AuthorizeAsync("AccessAdminPanel"))
                  return Challenge();
              return View();
          }

          public async Task<IActionResult> Me()
          {
              var user = await _userManager.GetUserAsync(User);
              if (user == null)
                  return Challenge();
              return View();
          }
      }
      CS
    admin = aspnet_tags(files, "Controllers.cs", 3)
    admin.map(&.name).should eq(["auth"])
    requires_of(admin[0]).should eq([["unresolved"]])
    me = aspnet_tags(files, "Controllers.cs", 10)
    requires_of(me[0]).should eq([["authenticated"], ["unresolved"]])
  end

  it "reads a caller check beside some refusal as unread: it may turn away signed-in callers only" do
    files = {"Controllers.cs" => <<-CS}
      public class AccountController : Controller
      {
          public IActionResult Login()
          {
              if (User.Identity.IsAuthenticated) return Redirect("/");
              return View();
          }
      }
      CS
    tags = aspnet_tags(files, "Controllers.cs", 3)
    tags.map(&.description).should eq(["Protected by ASP.NET User.Identity.IsAuthenticated"])
    requires_of(tags[0]).should eq([["unresolved"]])
  end
end
