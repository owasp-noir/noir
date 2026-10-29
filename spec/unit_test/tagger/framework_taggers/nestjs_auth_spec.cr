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

  it "walks past statements inside a multi-line decorator argument" do
    tmpdir = File.tempname("nest_callback_decorator")
    Dir.mkdir_p(tmpdir)
    path = File.join(tmpdir, "files.controller.ts")
    File.write(path, [
      "@Controller(\"files\")",                         # 1
      "export class FilesController {",                 # 2
      "  @UseGuards(AuthGuard(\"jwt\"))",               # 3
      "  @UseInterceptors(FileInterceptor(\"file\", {", # 4
      "    fileFilter: (req, file, cb) => {",           # 5
      "      cb(null, true);",                          # 6
      "    },",                                         # 7
      "  }))",                                          # 8
      "  @Post(\"upload\")",                            # 9
      "  upload() {",                                   # 10
      "    return 1;",                                  # 11
      "  }",                                            # 12
      "}",                                              # 13
    ].join("\n"))

    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(tmpdir)

    upload = Endpoint.new("/files/upload", "POST", [] of Param, Details.new(PathInfo.new(path, 9)))
    upload.details.technology = "ts_nestjs"

    NestjsAuthTagger.new(noir_options).perform([upload])

    upload.tags.map(&.name).should eq(["auth"])

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

  it "follows what the global guard does with the metadata its decorators set" do
    CodeLocator.instance.clear_all
    base = File.expand_path("../../../functional_test/fixtures/javascript/nestjs_auth_metadata", __DIR__)
    Dir.glob("#{base}/**/*").each { |path| CodeLocator.instance.register_path(path) if File.file?(path) }
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    routes = {
      # `if (options.public) return true`; no metadata throws.
      "ping"   => {"options/src/photos.controller.ts", 6},
      "shared" => {"options/src/photos.controller.ts", 10},
      "perm"   => {"options/src/photos.controller.ts", 14},
      "admin"  => {"options/src/photos.controller.ts", 18},
      "noperm" => {"options/src/photos.controller.ts", 22},
      "bare"   => {"options/src/photos.controller.ts", 26},
      # `if (isPublic) return true` over `SetMetadata(IS_PUBLIC_KEY, true)`.
      "public" => {"public/src/cats.controller.ts", 7},
      "guests" => {"public/src/cats.controller.ts", 11},
      "jwt"    => {"public/src/cats.controller.ts", 14},
      # `if (!options) return true`: only decorated routes authenticate.
      "open"    => {"opt_in/src/notes.controller.ts", 6},
      "secured" => {"opt_in/src/notes.controller.ts", 9},
      # `if (!roles) return true` after the guard read the request.
      "items" => {"afterauth/src/items.controller.ts", 5},
    }
    endpoints = routes.transform_values do |(file, line)|
      details = Details.new(PathInfo.new(File.join(base, file), line))
      details.technology = "ts_nestjs"
      Endpoint.new("/x", "GET", [] of Param, details)
    end

    NestjsAuthTagger.new(noir_options).perform(endpoints.values)
    tags = endpoints.transform_values(&.tags.map { |tag| "#{tag.name}: #{tag.description}" })

    tags["ping"].should eq(["anonymous: NestJS global APP_GUARD (AuthGuard) admits anonymous callers on @Authenticated({ public: true })"])
    tags["shared"].should eq(["auth: Protected by NestJS global APP_GUARD (AuthGuard) with @Authenticated({ sharedLink: true })",
                              "authz: Protected by NestJS @Authenticated({ permission: 'photo.read' })"])
    tags["perm"].should eq(["auth: Protected by NestJS global APP_GUARD (AuthGuard)",
                            "authz: Protected by NestJS @Authenticated({ permission: 'photo.create' })"])
    tags["admin"].should eq(["auth: Protected by NestJS global APP_GUARD (AuthGuard)",
                             "authz: Protected by NestJS @Authenticated({ admin: true })"])
    tags["noperm"].should eq(["auth: Protected by NestJS global APP_GUARD (AuthGuard)"])
    tags["bare"].should eq(["auth: Protected by NestJS global APP_GUARD (AuthGuard)"])
    tags["public"].should eq(["anonymous: NestJS global APP_GUARD (JwtAuthGuard) admits anonymous callers on @Public()"])
    tags["guests"].should eq(["anonymous: NestJS global APP_GUARD (JwtAuthGuard) admits anonymous callers on @OpenToGuests()"])
    tags["jwt"].should eq(["auth: Protected by NestJS global APP_GUARD (JwtAuthGuard)"])
    tags["open"].should eq(["anonymous: NestJS global APP_GUARD (SessionAuthGuard) admits anonymous callers on routes without its metadata"])
    tags["secured"].should eq(["auth: Protected by NestJS global APP_GUARD (SessionAuthGuard)"])
    tags["items"].should eq(["auth: Protected by NestJS global APP_GUARD (TokenAuthGuard)"])
  ensure
    CodeLocator.instance.clear_all
  end

  it "reads class guards past a tall docs block, any guard in the list, and optional Passport guards" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("nest_optional_guard")
    files = {
      "package.json"               => "{}",
      "src/api-auth.guard.ts"      => "export class ApiAuthGuard extends AuthGuard(\"api\") {}\n",
      "src/optional-auth.guard.ts" => <<-TS,
        export class OptionalAuthGuard extends ApiAuthGuard {
          handleRequest(error: Error, user: any) {
            if (user || !error) {
              return user || null;
            }
            throw error;
          }
        }
        TS
      "src/items.controller.ts" => <<-TS,
        @Controller({
          path: "/items",
        })
        @UseGuards(ApiAuthGuard)
        @ApiHeader({
          name: "cal-api-version",
          description: "Must be set",
          example: "2024-06-11",
          required: true,
          schema: {
            default: "2024-06-11",
          },
        })
        @ApiHeader(TOKEN_HEADER)
        export class ItemsController {
          @Get("/")
          list() {}

          @Get("/open")
          @UseGuards(OptionalAuthGuard)
          open() {}
        }

        @Controller("other")
        export class OtherController {
          @Get("/a")
          @UseGuards(BookingUidGuard, ApiAuthGuard)
          a() {}

          @Get("/b")
          @UseGuards(BookingUidGuard, OptionalAuthGuard)
          b() {}
        }
        TS
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
      controller = File.join(tmpdir, "src/items.controller.ts")
      endpoints = {"list" => 16, "open" => 19, "a" => 26, "b" => 30}.transform_values do |line|
        details = Details.new(PathInfo.new(controller, line))
        details.technology = "ts_nestjs"
        Endpoint.new("/x", "GET", [] of Param, details)
      end

      NestjsAuthTagger.new(noir_options).perform(endpoints.values)
      tags = endpoints.transform_values(&.tags.map { |tag| "#{tag.name}: #{tag.description}" })

      # `@UseGuards` sits eleven lines above the class.
      tags["list"].should eq(["auth: Protected by NestJS auth guard (class-level)"])
      # The class guard still runs before the optional one.
      tags["open"].should eq(["auth: Protected by NestJS auth guard (class-level)"])
      tags["a"].should eq(["auth: Protected by NestJS auth guard"])
      tags["b"].should eq(["anonymous: NestJS @UseGuards(BookingUidGuard, OptionalAuthGuard) admits anonymous callers: its handleRequest returns no user instead of throwing"])
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "reads a project decorator that bundles UseGuards by the guards' definitions" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("nest_guard_decorator")
    files = {
      "package.json"           => "{}",
      "src/user-auth.guard.ts" => "export class UserAuthGuard extends AuthGuard([\"jwt\", \"apikey\"]) {}\n",
      "src/api-key.guard.ts"   => <<-TS,
        export class ApiKeyGuard implements CanActivate {
          canActivate(context: ExecutionContext) {
            if (!context.switchToHttp().getRequest().headers["x-api-key"]) throw new UnauthorizedException();
            return true;
          }
        }
        export class LogsGuard implements CanActivate {
          canActivate() { return true; }
        }
        TS
      "src/auth.decorator.ts" => <<-TS,
        export function RequireAuthentication() {
          if (enterprise()) {
            return EnterpriseAuth();
          }
          return applyDecorators(UseGuards(UserAuthGuard), ApiBearerAuth());
        }
        export const RequireKey = () => applyDecorators(UseGuards(ApiKeyGuard));
        export const Logged = () => applyDecorators(UseGuards(LogsGuard), ApiTags("x"));
        TS
      "src/items.controller.ts" => <<-TS,
        @Controller("items")
        export class ItemsController {
          @Post("/login")
          login() {}

          @Post("/switch")
          @RequireAuthentication()
          switch() {}

          @Get("/key")
          @RequireKey()
          key() {}

          @Get("/logged")
          @Logged()
          logged() {}
        }

        @RequireAuthentication()
        @Controller("events")
        export class EventsController {
          @Delete("/:id")
          remove() {}
        }
        TS
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
      controller = File.join(tmpdir, "src/items.controller.ts")
      endpoints = {"login" => 4, "switch" => 8, "key" => 12, "logged" => 16, "remove" => 23}.transform_values do |line|
        details = Details.new(PathInfo.new(controller, line))
        details.technology = "ts_nestjs"
        Endpoint.new("/x", "GET", [] of Param, details)
      end

      NestjsAuthTagger.new(noir_options).perform(endpoints.values)
      tags = endpoints.transform_values(&.tags.map { |tag| "#{tag.name}: #{tag.description}" })

      tags["login"].should be_empty
      tags["switch"].should eq(["auth: Protected by NestJS @RequireAuthentication() (applies UseGuards(UserAuthGuard))"])
      # No `Auth` in the name: its `canActivate` throws Unauthorized.
      tags["key"].should eq(["auth: Protected by NestJS @RequireKey() (applies UseGuards(ApiKeyGuard))"])
      # Its guard always returns true.
      tags["logged"].should be_empty
      tags["remove"].first.should start_with("auth: Protected by NestJS @RequireAuthentication() (applies UseGuards(UserAuthGuard))")
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  it "resolves a guard decorator through the using file's import and judges direct and bundled guards alike" do
    CodeLocator.instance.clear_all
    tmpdir = File.tempname("nest_guard_decorator_scope")
    files = {
      "apps/a/package.json"     => "{}",
      "apps/a/src/jwt.guard.ts" => <<-TS,
        export class JwtGuard implements CanActivate {
          canActivate(ctx) { if (!ctx.user) throw new UnauthorizedException(); return true; }
        }
        TS
      "apps/a/src/auth.decorator.ts" => <<-TS,
        export function Auth() {
          return applyDecorators(UseGuards(JwtGuard), ApiBearerAuth());
        }
        TS
      "apps/a/src/sec.controller.ts" => <<-TS,
        import { Auth } from './auth.decorator';
        @Controller('sec')
        export class SecController {
          @Auth()
          @Get()
          list() {}
        }
        TS
      "apps/b/package.json"          => "{}",
      "apps/b/src/auth.decorator.ts" => <<-TS,
        export function Auth() {
          return applyDecorators(ApiBearerAuth(), ApiTags('auth'));
        }
        export class Helpers {
          static secured() {
            return applyDecorators(UseGuards(TokenAuthGuard));
          }
        }
        TS
      "apps/b/src/open.controller.ts" => <<-TS,
        import { Auth } from './auth.decorator';
        @Controller('open')
        export class OpenController {
          @Auth()
          @Get()
          list() {}
        }
        TS
      "apps/b/src/key.guard.ts" => <<-TS,
        export class ApiKeyGuard implements CanActivate {
          canActivate(ctx) { return ctx.switchToHttp().getRequest().headers['x-api-key'] === process.env.KEY; }
        }
        export class AuthStubGuard implements CanActivate {
          canActivate() { return true; }
        }
        export class PermsGuard implements CanActivate {
          canActivate(ctx) {
            const required = this.reflector.get(Perms, ctx.getHandler());
            if (!required) return true;
            if (!ctx.switchToHttp().getRequest().headers.authorization) throw new ForbiddenException();
            return true;
          }
        }
        export function KeyOnly() {
          return applyDecorators(UseGuards(ApiKeyGuard));
        }
        TS
      "apps/b/src/key.controller.ts" => <<-TS,
        import { KeyOnly } from './key.guard';
        @Controller('key')
        export class KeyController {
          @KeyOnly()
          @Get('bundled')
          bundled() {}

          @UseGuards(ApiKeyGuard)
          @Get('direct')
          direct() {}

          @UseGuards(AuthStubGuard)
          @Get('stub')
          stub() {}

          @UseGuards(PermsGuard)
          @Get('perms')
          perms() {}
        }
        TS
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
      lines = {
        "sec"     => {"apps/a/src/sec.controller.ts", 6},
        "open"    => {"apps/b/src/open.controller.ts", 6},
        "bundled" => {"apps/b/src/key.controller.ts", 6},
        "direct"  => {"apps/b/src/key.controller.ts", 10},
        "stub"    => {"apps/b/src/key.controller.ts", 14},
        "perms"   => {"apps/b/src/key.controller.ts", 18},
      }
      endpoints = lines.transform_values do |(rel, line)|
        details = Details.new(PathInfo.new(File.join(tmpdir, rel), line))
        details.technology = "ts_nestjs"
        Endpoint.new("/x", "GET", [] of Param, details)
      end

      NestjsAuthTagger.new(noir_options).perform(endpoints.values)
      tags = endpoints.transform_values(&.tags.map { |tag| "#{tag.name}: #{tag.description}" })

      tags["sec"].should eq(["auth: Protected by NestJS @Auth() (applies UseGuards(JwtGuard))"])
      # apps/b's own `Auth()` only documents; the static method's
      # applyDecorators belongs to `Helpers`, not to it.
      tags["open"].should be_empty
      # `false` from canActivate is a 403 to a caller without the key.
      tags["bundled"].should eq(["auth: Protected by NestJS @KeyOnly() (applies UseGuards(ApiKeyGuard))"])
      tags["direct"].should eq(["auth: Protected by NestJS @UseGuards(ApiKeyGuard)"])
      # Named like an auth guard, but its definition lets everyone through.
      tags["stub"].should be_empty
      # Lets a route without its metadata through; its name says nothing.
      tags["perms"].should be_empty
    ensure
      FileUtils.rm_rf(tmpdir)
      CodeLocator.instance.clear_all
    end
  end

  # nestjs_global_guard_site: `JwtAuthGuard` registered as APP_GUARD in
  # app.module.ts and declared at line 5 of jwt-auth.guard.ts (#3308).
  it "locates a global APP_GUARD tag at the guard's class" do
    base = File.expand_path("../../../functional_test/fixtures/javascript/nestjs_global_guard_site", __DIR__)
    noir_options = create_test_options
    noir_options["base"] = YAML::Any.new(base)
    Dir.glob("#{base}/src/*.ts").each { |path| CodeLocator.instance.register_path(path) }
    details = Details.new(PathInfo.new("#{base}/src/items.controller.ts", 5))
    details.technology = "ts_nestjs"
    endpoint = Endpoint.new("/items", "GET", [] of Param, details)

    endpoint = NestjsAuthTagger.new(noir_options).perform([endpoint]).first
    tag = endpoint.tags.find! { |t| t.name == "auth" }
    tag.description.should eq("Protected by NestJS global APP_GUARD (JwtAuthGuard)")
    tag.path.should eq("#{base}/src/jwt-auth.guard.ts")
    tag.line.should eq(5)
  end

  it "locates a passport APP_GUARD at its class, past a commented-out one" do
    tmpdir = File.tempname("nest_passport_guard_site")
    Dir.mkdir_p("#{tmpdir}/src")
    File.write("#{tmpdir}/package.json", %({"dependencies":{"@nestjs/core":"^10.0.0"}}))
    File.write("#{tmpdir}/src/app.module.ts", "@Module({ providers: [{ provide: APP_GUARD, useClass: JwtAuthGuard }] })\nexport class AppModule {}\n")
    File.write("#{tmpdir}/src/jwt.guard.ts", "/**\n * class JwtAuthGuard example\n */\n@Injectable()\nexport class JwtAuthGuard extends AuthGuard('jwt') {}\n")
    File.write("#{tmpdir}/src/items.controller.ts", "@Controller('items')\nexport class ItemsController {\n  @Get()\n  list() { return []; }\n}\n")
    begin
      noir_options = create_test_options
      noir_options["base"] = YAML::Any.new(tmpdir)
      Dir.glob("#{tmpdir}/src/*.ts").each { |path| CodeLocator.instance.register_path(path) }
      details = Details.new(PathInfo.new("#{tmpdir}/src/items.controller.ts", 3))
      details.technology = "ts_nestjs"
      endpoint = NestjsAuthTagger.new(noir_options).perform([Endpoint.new("/items", "GET", [] of Param, details)]).first
      tag = endpoint.tags.find! { |t| t.name == "auth" }
      tag.path.should eq("#{tmpdir}/src/jwt.guard.ts")
      tag.line.should eq(5)
    ensure
      FileUtils.rm_rf(tmpdir)
    end
  end
end
