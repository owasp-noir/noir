require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `files` (plus a `package.json`) under a temp dir, tags one GET
# endpoint whose handler is `src/c.controller.ts` at `line`, and returns
# each tag's distinct clauses as atom strings, unresolved ones with their text.
private def nest_requires(files : Hash(String, String), line : Int32, technology : String = "ts_nestjs", url : String = "/c") : Hash(String, Array(Array(String))?)
  CodeLocator.instance.clear_all
  tmpdir = File.tempname("nest_requires")
  files.merge({"package.json" => "{}"}).each do |rel, body|
    path = File.join(tmpdir, rel)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, body)
    CodeLocator.instance.register_path(path)
  end
  options = create_test_options
  options["base"] = YAML::Any.new(tmpdir)
  details = Details.new(PathInfo.new(File.join(tmpdir, "src/c.controller.ts"), line))
  details.technology = technology
  endpoint = NestjsAuthTagger.new(options).perform([Endpoint.new(url, "GET", [] of Param, details)])[0]
  endpoint.tags.to_h do |tag|
    {tag.name, tag.requires.try(&.map(&.any_of.map { |atom| atom.kind.unresolved? ? "unresolved:#{atom.value}" : atom.to_s }).uniq!)}
  end
ensure
  FileUtils.rm_rf(tmpdir) if tmpdir
  CodeLocator.instance.clear_all
end

# A controller whose handler sits on line 5.
private def controller(class_decorators : String, method_decorators : String, prelude : String = "") : String
  "#{prelude}\n#{class_decorators}\n@Controller('c')\nexport class C {\n  #{method_decorators} @Get() m() {}\n}\n"
end

PLAIN_JWT = "export class JwtAuthGuard extends AuthGuard('jwt') {}\n"

describe "NestjsAuthTagger requires" do
  it "reads a plain Passport guard and @Roles literals, keeping an enum from another file unresolved" do
    files = {
      "src/jwt.guard.ts"    => PLAIN_JWT,
      "src/c.controller.ts" => controller("@UseGuards(JwtAuthGuard, RolesGuard)", "@Roles('admin', Role.Admin)"),
    }
    nest_requires(files, 5).should eq({
      "auth"  => [["authenticated"]],
      "authz" => [["role:admin", "unresolved:Role.Admin"]],
    })
  end

  it "resolves an enum member declared in the controller's file" do
    files = {"src/c.controller.ts" => controller("", "@UseGuards(AuthGuard('jwt')) @Roles(Role.Admin)", "enum Role { Admin = 'admin' }")}
    nest_requires(files, 5).should eq({"auth" => [["authenticated"]], "authz" => [["role:admin"]]})
  end

  it "keeps the class @Roles beside the method's, which override or merge per guard" do
    files = {"src/c.controller.ts" => controller("@Roles('admin')", "@Roles('editor')")}
    nest_requires(files, 5).should eq({"authz" => [["role:editor", "unresolved:@Roles('admin')"]]})
    files = {"src/c.controller.ts" => controller("@Roles('admin')", "@Permissions('posts:write')")}
    nest_requires(files, 5).should eq({"authz" => [["permission:posts:write"], ["role:admin"]]})
  end

  it "adds every guard of the class and the method, each unread unless it is a plain Passport guard" do
    files = {
      "src/admin.guard.ts"  => "export class AdminJwtGuard extends AuthGuard('jwt') {\n  canActivate(ctx) { return super.canActivate(ctx); }\n}\n",
      "src/c.controller.ts" => controller("@UseGuards(AdminJwtGuard)", "@UseGuards(AuthGuard(JWT_STRATEGY), BookingGuard, ThrottlerGuard)"),
    }
    nest_requires(files, 5).should eq({"auth" => [
      ["authenticated"], ["unresolved:AuthGuard(JWT_STRATEGY)"], ["unresolved:AdminJwtGuard"], ["unresolved:BookingGuard"],
    ]})
  end

  it "reads a guard that also runs the anonymous strategy as unresolved alone" do
    files = {
      "src/optional.guard.ts" => "export class MaybeJwtAuthGuard extends AuthGuard(['jwt', 'anonymous']) {}\n",
      "src/c.controller.ts"   => controller("", "@UseGuards(AuthGuard(['jwt', 'anonymous']))"),
    }
    nest_requires(files, 5).should eq({"auth" => [["unresolved:AuthGuard(['jwt', 'anonymous'])"]]})
    files["src/c.controller.ts"] = controller("@UseGuards(MaybeJwtAuthGuard)", "")
    nest_requires(files, 5).should eq({"auth" => [["unresolved:MaybeJwtAuthGuard"]]})
  end

  it "adds @Scopes and CASL policies to the auth tag when no authz tag is emitted" do
    files = {
      "src/jwt.guard.ts"    => PLAIN_JWT,
      "src/c.controller.ts" => controller("@UseGuards(JwtAuthGuard)", "@Scopes('read') @CheckPolicies((ability) => ability.can(Action.Read, Post))"),
    }
    nest_requires(files, 5).should eq({"auth" => [
      ["authenticated"], ["scope:read"], ["unresolved:@CheckPolicies((ability) => ability.can(Action.Read, Post))"],
    ]})
  end

  it "adds a route's guards to a middleware tag when no decorator tag is emitted" do
    files = {
      "src/app.module.ts"       => "export class AppModule {\n  configure(consumer) {\n    consumer.apply(TokenMiddleware).forRoutes(C);\n  }\n}\n",
      "src/token.middleware.ts" => "export class TokenMiddleware {\n  use(req, res, next) {\n    if (!req.headers.authorization) throw new UnauthorizedException();\n    next();\n  }\n}\n",
      "src/c.controller.ts"     => controller("", "@UseGuards(BookingGuard)"),
    }
    nest_requires(files, 5).should eq({"auth" => [
      ["authenticated"], ["unresolved:NestJS TokenMiddleware middleware"], ["unresolved:BookingGuard"],
    ]})
  end

  it "reads a bound RolesGuard with no metadata as unresolved" do
    files = {
      "src/jwt.guard.ts"    => PLAIN_JWT,
      "src/c.controller.ts" => controller("@UseGuards(JwtAuthGuard, RolesGuard)", ""),
    }
    nest_requires(files, 5).should eq({"auth" => [["authenticated"]], "authz" => [["unresolved:@UseGuards(JwtAuthGuard, RolesGuard)"]]})
  end

  it "adds a forRoutes middleware's clauses to the decorator guard's under one auth tag" do
    files = {
      "src/app.module.ts"       => "export class AppModule {\n  configure(consumer) {\n    consumer.apply(TokenMiddleware).forRoutes(C);\n  }\n}\n",
      "src/token.middleware.ts" => "export class TokenMiddleware {\n  use(req, res, next) {\n    if (!req.headers.authorization) throw new UnauthorizedException();\n    next();\n  }\n}\n",
      "src/c.controller.ts"     => controller("", "@UseGuards(AuthGuard('jwt'))"),
    }
    nest_requires(files, 5).should eq({"auth" => [
      ["authenticated"], ["unresolved:NestJS TokenMiddleware middleware"],
    ]})
  end

  it "adds a global guard to a route that binds its own" do
    files = {
      "src/app.module.ts"    => "@Module({ providers: [{ provide: APP_GUARD, useClass: SessionAuthGuard }] })\nexport class AppModule {}\n",
      "src/session.guard.ts" => "export class SessionAuthGuard {\n  canActivate(ctx) {\n    if (!ctx.switchToHttp().getRequest().session) throw new UnauthorizedException();\n    return true;\n  }\n}\n",
      "src/c.controller.ts"  => controller("", "@UseGuards(AuthGuard('jwt'))"),
    }
    nest_requires(files, 5).should eq({"auth" => [
      ["authenticated"], ["unresolved:SessionAuthGuard"],
    ]})
  end

  it "reads decorators of other frameworks and Swagger-only evidence as an unread guard" do
    files = {"src/c.controller.ts" => controller("", "@Security('jwt', ['admin'])")}
    nest_requires(files, 5, "ts_tsoa").should eq({"auth" => [["authenticated"], ["unresolved:@Security('jwt', ['admin'])"]]})
    files = {"src/c.controller.ts" => controller("", "@ApiBearerAuth()")}
    nest_requires(files, 5).should eq({"auth" => [["authenticated"], ["unresolved:NestJS @ApiBearerAuth (Swagger)"]]})
  end
end
