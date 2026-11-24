require "file_utils"
require "../../../spec_helper"
require "../../../../src/tagger/tagger"

# Writes `files` (plus a `package.json`) under a temp dir, tags one GET
# endpoint whose handler is `src/c.controller.ts` at `line`, and returns
# each tag's distinct clauses as atom strings, unresolved ones with their text.
private def nest_requires(files : Hash(String, String), line : Int32, technology : String = "ts_nestjs", url : String = "/c", handler : String = "src/c.controller.ts") : Hash(String, Array(Array(String))?)
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
  details = Details.new(PathInfo.new(File.join(tmpdir, handler), line))
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

# A `RolesGuard` whose Reflector call is `read` and whose check is `check`.
private def roles_guard(read : String, check : String) : String
  "export class RolesGuard {\n  canActivate(context) {\n    const roles = this.reflector.#{read};\n    if (!roles) return true;\n    const user = context.switchToHttp().getRequest().user;\n    return #{check};\n  }\n}\n"
end

HANDLER_EVERY = roles_guard("get('roles', context.getHandler())", "roles.every((role) => user.roles.includes(role))")
OVERRIDE_SOME = roles_guard("getAllAndOverride('roles', [context.getHandler(), context.getClass()])", "roles.some((role) => user.roles.includes(role))")

describe "NestjsAuthTagger requires" do
  it "reads @Roles under a RolesGuard whose source is not at hand, keeping an enum from another file and the unread combination unresolved" do
    files = {
      "src/jwt.guard.ts"    => PLAIN_JWT,
      "src/c.controller.ts" => controller("@UseGuards(JwtAuthGuard, RolesGuard)", "@Roles('admin', Role.Admin)"),
    }
    nest_requires(files, 5).should eq({
      "auth"  => [["authenticated"]],
      "authz" => [["role:admin", "unresolved:Role.Admin"], ["unresolved:@Roles('admin', Role.Admin)"]],
    })
  end

  it "resolves an enum member declared in the controller's file" do
    files = {"src/c.controller.ts" => controller("", "@UseGuards(AuthGuard('jwt'), RolesGuard) @Roles(Role.Admin)", "enum Role { Admin = 'admin' }")}
    nest_requires(files, 5).should eq({"auth" => [["authenticated"]], "authz" => [["role:admin"]]})
  end

  it "keeps a metadata check no visible guard reads as an alternative" do
    files = {
      "src/jwt.guard.ts"    => PLAIN_JWT,
      "src/c.controller.ts" => controller("@UseGuards(JwtAuthGuard)", "@Roles('admin')"),
    }
    nest_requires(files, 5).should eq({"auth" => [["authenticated"]], "authz" => [["role:admin", "unresolved:@Roles('admin')"]]})
    files["src/app.module.ts"] = "@Module({ providers: [{ provide: APP_GUARD, useClass: RolesGuard }] })\nexport class AppModule {}\n"
    files["src/roles.guard.ts"] = OVERRIDE_SOME
    nest_requires(files, 5).should eq({"auth" => [["authenticated"]], "authz" => [["role:admin"]]})
  end

  it "reads several roles by the bound guard's check" do
    files = {"src/roles.guard.ts" => HANDLER_EVERY, "src/c.controller.ts" => controller("@UseGuards(RolesGuard)", "@Roles('admin', 'user')")}
    nest_requires(files, 5).should eq({"authz" => [["role:admin"], ["role:user"]]})
    files["src/roles.guard.ts"] = OVERRIDE_SOME
    nest_requires(files, 5).should eq({"authz" => [["role:admin", "role:user"]]})
  end

  it "counts class @Roles only when the bound guard reads class metadata" do
    files = {"src/roles.guard.ts" => HANDLER_EVERY, "src/c.controller.ts" => controller("@UseGuards(RolesGuard) @Roles('admin')", "")}
    nest_requires(files, 5).should eq({"authz" => [["unresolved:@UseGuards(RolesGuard)"]]})
    files["src/roles.guard.ts"] = OVERRIDE_SOME
    nest_requires(files, 5).should eq({"authz" => [["role:admin"]]})
    files["src/c.controller.ts"] = controller("@UseGuards(RolesGuard) @Roles('admin')", "@Roles('editor') @Permissions('posts:write')")
    nest_requires(files, 5).should eq({"authz" => [["role:editor"], ["permission:posts:write", "unresolved:@Permissions('posts:write')"]]})
  end

  it "reads only the top-most of two metadata decorators of one kind" do
    files = {"src/roles.guard.ts" => OVERRIDE_SOME, "src/c.controller.ts" => controller("@UseGuards(RolesGuard)", "@Roles('admin') @Roles('user')")}
    nest_requires(files, 5).should eq({"authz" => [["role:admin"]]})
  end

  it "judges a guard class by its own app's definition" do
    files = {
      "apps/a/package.json"     => "{}",
      "apps/a/src/jwt.guard.ts" => "export class JwtAuthGuard extends AuthGuard('jwt') {\n  handleRequest(err, user) {\n    if (!user.isStaff) throw new ForbiddenException();\n    return user;\n  }\n}\n",
      "apps/a/src/k.ts"         => controller("@UseGuards(JwtAuthGuard)", ""),
      "apps/b/package.json"     => "{}",
      "apps/b/src/jwt.guard.ts" => PLAIN_JWT,
      "apps/b/src/k.ts"         => controller("@UseGuards(JwtAuthGuard)", ""),
    }
    nest_requires(files, 5, handler: "apps/a/src/k.ts").should eq({"auth" => [["authenticated"], ["unresolved:JwtAuthGuard"]]})
    nest_requires(files, 5, handler: "apps/b/src/k.ts").should eq({"auth" => [["authenticated"]]})
  end

  it "keeps the other bound guards on a route an optional guard or a global guard's skip opens" do
    files = {
      "src/guards.ts"       => "export class OptionalJwtAuthGuard extends AuthGuard('jwt') {\n  handleRequest(err, user) {\n    return user || null;\n  }\n}\n",
      "src/c.controller.ts" => controller("", "@UseGuards(OptionalJwtAuthGuard, BookingGuard)"),
    }
    nest_requires(files, 5).should eq({"anonymous" => [["unresolved:BookingGuard"]]})
    files = {
      "src/app.module.ts"       => "@Module({ providers: [{ provide: APP_GUARD, useClass: GlobalAuthGuard }] })\nexport class AppModule {}\n",
      "src/global.guard.ts"     => "export class GlobalAuthGuard extends AuthGuard('jwt') {\n  canActivate(context) {\n    const isPublic = this.reflector.getAllAndOverride(IS_PUBLIC_KEY, [context.getHandler(), context.getClass()]);\n    if (isPublic) {\n      return true;\n    }\n    return super.canActivate(context);\n  }\n}\n",
      "src/public.decorator.ts" => "export const IS_PUBLIC_KEY = 'isPublic';\nexport const Public = () => SetMetadata(IS_PUBLIC_KEY, true);\n",
      "src/c.controller.ts"     => controller("", "@Public() @UseGuards(BookingGuard)"),
    }
    nest_requires(files, 5).should eq({"anonymous" => [["unresolved:BookingGuard"]]})
    files["src/c.controller.ts"] = controller("", "@Public()")
    nest_requires(files, 5).should eq({"anonymous" => nil})
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
      ["authenticated"], ["scope:read", "unresolved:@Scopes('read')"], ["unresolved:@CheckPolicies((ability) => ability.can(Action.Read, Post))"],
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
