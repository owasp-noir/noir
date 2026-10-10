require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

describe "NestjsAuthTagger" do
  fixture_base = File.expand_path("../../../functional_test/fixtures/javascript/nestjs_auth", __DIR__)
  controller_path = "#{fixture_base}/src/posts.controller.ts"

  # posts.controller.ts line reference:
  #  8: @Controller('posts')
  #  9: @UseGuards(JwtAuthGuard)
  # 10: export class PostsController {
  # 12:   @Public()
  # 13:   @Get()
  # 14:   findAll() {
  # 18:   @Get(':id')
  # 19:   findOne() {
  # 23:   @Roles('admin')
  # 24:   @Post()
  # 25:   create() {
  # 29:   @Roles('admin')
  # 30:   @Delete(':id')
  # 31:   remove() {

  before_each do
    CodeLocator.instance.clear_all
  end

  it "detects class-level @UseGuards(JwtAuthGuard) on non-public action" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 19))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts/1", "GET", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_false
    endpoint.tags[0].name.should eq("auth")
    endpoint.tags[0].tagger.should eq("nestjs_auth")
    endpoint.tags[0].description.should contain("JwtAuthGuard")
  end

  it "respects @Public() decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 14))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts", "GET", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.empty?.should be_true
  end

  it "detects @Roles decorator" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 25))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts", "POST", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.any? { |t| t.name == "authz" && t.description.includes?("@Roles") }.should be_true
  end

  it "stacks class JwtAuthGuard authn with method @Roles authz" do
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(fixture_base)

    details = Details.new(PathInfo.new(controller_path, 31))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts/:id", "DELETE", [] of Param, details)

    tagger = NestjsAuthTagger.new(noir_options)
    tagger.perform([endpoint])

    endpoint.tags.map(&.name).sort!.should eq(["auth", "authz"])
    endpoint.tags.find! { |t| t.name == "auth" }.description.should contain("JwtAuthGuard")
    endpoint.tags.find! { |t| t.name == "authz" }.description.should contain("@Roles")
  end

  it "detects RolesGuard anywhere in combined @UseGuards(JwtAuthGuard, RolesGuard)" do
    tmpdir = File.tempname("nestjs_combined_guards")
    Dir.mkdir_p(tmpdir)
    path = File.join(tmpdir, "posts.controller.ts")
    File.write(path, [
      "@Controller('posts')",
      "export class PostsController {",
      "  @UseGuards(JwtAuthGuard, RolesGuard)",
      "  @Delete(':id')",
      "  remove() {",
      "    return {};",
      "  }",
      "}",
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    details = Details.new(PathInfo.new(path, 5))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/posts/:id", "DELETE", [] of Param, details)

    NestjsAuthTagger.new(noir_options).perform([endpoint])

    endpoint.tags.map(&.name).sort!.should eq(["auth", "authz"])
    endpoint.tags.find! { |t| t.name == "auth" }.description.should contain("JwtAuthGuard")
    endpoint.tags.find! { |t| t.name == "authz" }.description.should contain("RolesGuard")

    FileUtils.rm_rf(tmpdir)
  end

  it "tags tsoa @Security without leaking it into the next non-async handler" do
    tmpdir = File.tempname("tsoa_security")
    Dir.mkdir_p(tmpdir)
    path = File.join(tmpdir, "usersController.ts")
    File.write(path, [
      "@Route(\"users\")",                 # 1
      "export class UsersController {",    # 2
      "  @Security(\"jwt\")",              # 3
      "  @Post()",                         # 4
      "  createUser(@Body() body: any) {", # 5
      "    return body;",                  # 6
      "  }",                               # 7
      "",                                  # 8
      "  @Get(\"{id}\")",                  # 9
      "  getUser(@Path() id: number) {",   # 10
      "    return id;",                    # 11
      "  }",                               # 12
      "}",                                 # 13
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    secured = Endpoint.new("/users", "POST", [] of Param, Details.new(PathInfo.new(path, 4)))
    secured.details.technology = "ts_tsoa"
    open = Endpoint.new("/users/{id}", "GET", [] of Param, Details.new(PathInfo.new(path, 9)))
    open.details.technology = "ts_tsoa"

    NestjsAuthTagger.new(noir_options).perform([secured, open])

    secured.tags.map(&.name).should eq(["auth"])
    secured.tags.first.description.should contain("@Security")
    open.tags.should be_empty

    FileUtils.rm_rf(tmpdir)
  end

  it "does not leak a decorator past a one-line handler body" do
    tmpdir = File.tempname("tsoa_one_line")
    Dir.mkdir_p(tmpdir)
    path = File.join(tmpdir, "openController.ts")
    File.write(path, [
      "@Route(\"open\")",                                 # 1
      "export class OpenController extends Controller {", # 2
      "  @Security(\"api_key\")",                         # 3
      "  @Post(\"c\")",                                   # 4
      "  public c() {}",                                  # 5
      "",                                                 # 6
      "  @Get(\"d\")",                                    # 7
      "  public d() {}",                                  # 8
      "}",                                                # 9
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    secured = Endpoint.new("/open/c", "POST", [] of Param, Details.new(PathInfo.new(path, 4)))
    secured.details.technology = "ts_tsoa"
    open = Endpoint.new("/open/d", "GET", [] of Param, Details.new(PathInfo.new(path, 7)))
    open.details.technology = "ts_tsoa"

    NestjsAuthTagger.new(noir_options).perform([secured, open])

    secured.tags.map(&.name).should eq(["auth"])
    open.tags.should be_empty

    FileUtils.rm_rf(tmpdir)
  end

  it "applies a global APP_GUARD auth guard unless the handler or controller is @Public()" do
    tmpdir = File.tempname("nest_global_guard")
    Dir.mkdir_p(tmpdir)
    mod = File.join(tmpdir, "app.module.ts")
    cats = File.join(tmpdir, "cats.controller.ts")
    health = File.join(tmpdir, "health.controller.ts")
    File.write(mod, <<-TS)
      @Module({
        providers: [
          { provide: APP_GUARD, useClass: ThrottlerGuard },
          {
            provide: APP_GUARD,
            useClass: JwtAuthGuard,
          },
        ],
      })
      export class AppModule {}
      TS
    File.write(cats, <<-TS)
      @Controller('cats')
      export class CatsController {
        @Public()
        @Get()
        findAll() {}

        @Post()
        create() {}
      }
      TS
    File.write(health, <<-TS)
      @Public()
      @Controller('health')
      export class HealthController {
        @Get()
        check() {}
      }
      TS
    [mod, cats, health].each { |path| CodeLocator.instance.register_path(path) }

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)
    find_all = Endpoint.new("/cats", "GET", [] of Param, Details.new(PathInfo.new(cats, 5)))
    create = Endpoint.new("/cats", "POST", [] of Param, Details.new(PathInfo.new(cats, 8)))
    check = Endpoint.new("/health", "GET", [] of Param, Details.new(PathInfo.new(health, 5)))

    NestjsAuthTagger.new(noir_options).perform([find_all, create, check])

    find_all.tags.should be_empty
    create.tags.map(&.description).should eq(["Protected by NestJS global APP_GUARD (JwtAuthGuard)"])
    check.tags.should be_empty

    FileUtils.rm_rf(tmpdir)
  end

  it "reads a global guard only from live, non-test code of the endpoint's own app" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("nest_global_scope")
    controller = <<-TS
      @Controller('x')
      export class XController {
        @Get()
        find() {}
      }
      TS
    files = {
      "api/package.json"          => "{}",
      "api/src/app.module.ts"     => "// providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }]\n/* app.useGlobalGuards(new JwtAuthGuard()) */\n",
      "api/src/x.controller.ts"   => controller,
      "api/test/app.e2e-spec.ts"  => "app.useGlobalGuards(new JwtAuthGuard());\n",
      "api/src/auth.spec.ts"      => "const m = { provide: APP_GUARD, useClass: JwtAuthGuard };\n",
      "admin/package.json"        => "{}",
      "admin/src/main.ts"         => "app.useGlobalGuards(new JwtAuthGuard());\n",
      "admin/src/x.controller.ts" => controller,
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
      api = Endpoint.new("/x", "GET", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, "api/src/x.controller.ts"), 4)))
      admin = Endpoint.new("/x", "GET", [] of Param, Details.new(PathInfo.new(File.join(tmpdir, "admin/src/x.controller.ts"), 4)))

      NestjsAuthTagger.new(noir_options).perform([api, admin])

      api.tags.should be_empty
      admin.tags.map(&.description).should eq(["Protected by NestJS global APP_GUARD (JwtAuthGuard)"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end
end
