require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/java/java_access"

private def strings(cnf : Access::CNF?) : Array(Array(String))?
  cnf.try(&.map(&.sort.map(&.to_s)))
end

private def written(source : String) : JavaAccess::Annotation
  name = source.match!(/@(\w+)/)[1]
  JavaAccess.annotation_in(source.split('\n'), 0, name).not_nil!
end

private def vertx(text : String, last : Bool) : Array(Array(String))
  strings(JavaAccess.vertx_handler(text, last) { |rest| rest.matches?(/AuthHandler|AuthenticationHandler|JWTAuth|routingContext\.user\(\)/) }).not_nil!
end

describe JavaAccess do
  describe ".annotation_in" do
    it "reads arguments across lines up to the balanced parenthesis" do
      found = JavaAccess.annotation_in(["@RolesAllowed({", "  \"a\", \")\",", "  \"b\"})", "public String x()"], 0, "RolesAllowed").not_nil!
      found.args.should eq("{\n  \"a\", \")\",\n  \"b\"}")
      found.text.should eq("@RolesAllowed({ \"a\", \")\", \"b\"})")
    end

    it "is nil for a parenthesis that never closes" do
      JavaAccess.annotation_in(["@RolesAllowed({\"a\""], 0, "RolesAllowed").should be_nil
    end

    it "has no arguments without parentheses" do
      JavaAccess.annotation_in(["@jakarta.annotation.security.PermitAll"], 0, "PermitAll").not_nil!.args.should be_nil
    end
  end

  describe ".quarkus" do
    {
      "@Authenticated"                                                   => [["authenticated"]],
      "@PermitAll"                                                       => [] of Array(String),
      "@DenyAll"                                                         => [["deny"]],
      "@RolesAllowed(\"user\")"                                          => [["role:user"]],
      "@RolesAllowed({\"a\", \"ROLE_b\"})"                               => [["role:ROLE_b", "role:a"]],
      "@RolesAllowed(value = {\"a\"})"                                   => [["role:a"]],
      "@RolesAllowed(value = \"a\", other = \"b\")"                      => [["unresolved"]],
      "@RolesAllowed(\"a\", \"b\")"                                      => [["role:a", "role:b"]],
      "@RolesAllowed([\"a\", \"b\"])"                                    => [["role:a", "role:b"]],
      "@RolesAllowed(arrayOf(\"a\"))"                                    => [["role:a"]],
      "@RolesAllowed(\"**\")"                                            => [["authenticated"]],
      "@RolesAllowed(\"${admin.role}\")"                                 => [["unresolved"]],
      "@RolesAllowed({\"a\", Roles.B})"                                  => [["role:a", "unresolved"]],
      "@RolesAllowed({})"                                                => [["unresolved"]],
      "@RolesAllowed"                                                    => [["unresolved"]],
      "@PermissionsAllowed(\"read\")"                                    => [["permission:read"]],
      "@PermissionsAllowed({\"a\", \"b\"})"                              => [["permission:a", "permission:b"]],
      "@PermissionsAllowed(value = {\"a\", \"b\"}, inclusive = true)"    => [["permission:a"], ["permission:b"]],
      "@PermissionsAllowed(value = {\"a\", \"b\"}, inclusive = false)"   => [["permission:a", "permission:b"]],
      "@PermissionsAllowed(value = \"a\", inclusive = FLAG)"             => [["unresolved"]],
      "@PermissionsAllowed(value = \"list\", permission = Custom.class)" => [["unresolved"]],
      "@PermissionsAllowed(value = \"hi\", params = \"bean.name\")"      => [["unresolved"]],
      "@PermissionsAllowed(\"${perm}\")"                                 => [["unresolved"]],
    }.each do |source, expected|
      it "reads #{source}" do
        strings(JavaAccess.quarkus(written(source))).should eq(expected)
      end
    end

    it "leaves a permission an app @PermissionChecker decides unread" do
      strings(JavaAccess.quarkus(written("@PermissionsAllowed({\"rename\", \"read\"})"), Set{"rename"})).should eq([["permission:read", "unresolved"]])
      strings(JavaAccess.quarkus(written("@PermissionsAllowed(\"read\")"), nil)).should eq([["unresolved"]])
    end
  end

  describe ".quarkus_policy" do
    it "reads the built-in and role policies" do
      strings(JavaAccess.quarkus_policy("permit", nil, false)).should eq([] of Array(String))
      strings(JavaAccess.quarkus_policy("deny", nil, false)).should eq([["deny"]])
      strings(JavaAccess.quarkus_policy("authenticated", nil, false)).should eq([["authenticated"]])
      strings(JavaAccess.quarkus_policy("admins", "admin, user", true)).should eq([["role:admin", "role:user"]])
      strings(JavaAccess.quarkus_policy("admins", "**", true)).should eq([["authenticated"]])
      strings(JavaAccess.quarkus_policy("admins", "${role}", true)).should eq([["unresolved"]])
      strings(JavaAccess.quarkus_policy("admins", nil, true)).should eq([["authenticated"]])
      strings(JavaAccess.quarkus_policy("custom", nil, false)).should eq([["unresolved"]])
    end
  end

  describe ".micronaut" do
    {
      "@Secured(SecurityRule.IS_AUTHENTICATED)" => [["authenticated"]],
      "@Secured(\"isAuthenticated()\")"         => [["authenticated"]],
      "@Secured(IS_AUTHENTICATED)"              => [["authenticated"]],
      # The constants hold `"isAuthenticated()"`; this literal names a role.
      "@Secured(\"IS_AUTHENTICATED\")"                            => [["role:IS_AUTHENTICATED"]],
      "@Secured(\"IS_ANONYMOUS\")"                                => [["role:IS_ANONYMOUS"]],
      "@Secured(SecurityRule.IS_ANONYMOUS)"                       => [] of Array(String),
      "@Secured({\"ROLE_X\", SecurityRule.IS_ANONYMOUS})"         => [] of Array(String),
      "@Secured(SecurityRule.DENY_ALL)"                           => [["deny"]],
      "@Secured({SecurityRule.IS_ANONYMOUS, \"denyAll()\"})"      => [["deny"]],
      "@Secured({Roles.ADMIN, SecurityRule.DENY_ALL})"            => [["deny"]],
      "@Secured({\"ROLE_ADMIN\", \"ROLE_X\"})"                    => [["role:ROLE_ADMIN", "role:ROLE_X"]],
      "@Secured(\"ROLE_ADMIN\", \"ROLE_X\")"                      => [["role:ROLE_ADMIN", "role:ROLE_X"]],
      "@Secured(value = {\"ROLE_ADMIN\"})"                        => [["role:ROLE_ADMIN"]],
      "@Secured({\"ROLE_ADMIN\", Roles.X})"                       => [["unresolved"]],
      "@Secured(\"\#{ user?.attributes?.get('email') == 'a' }\")" => [["unresolved"]],
      "@Secured(\"${role}\")"                                     => [["unresolved"]],
      "@Secured({})"                                              => [["unresolved"]],
      "@Secured"                                                  => [["unresolved"]],
    }.each do |source, expected|
      it "reads #{source}" do
        strings(JavaAccess.micronaut(written(source))).should eq(expected)
      end
    end
  end

  describe ".vaadin" do
    it "follows AccessAnnotationChecker's precedence" do
      strings(JavaAccess.vaadin([written("@PermitAll")])).should eq([["authenticated"]])
      strings(JavaAccess.vaadin([written("@AnonymousAllowed")])).should eq([] of Array(String))
      strings(JavaAccess.vaadin([written("@DenyAll")])).should eq([["deny"]])
      strings(JavaAccess.vaadin([written("@RolesAllowed({\"ADMIN\", \"USER\"})")])).should eq([["authenticated"], ["role:ADMIN", "role:USER"]])
      strings(JavaAccess.vaadin([written("@PermitAll"), written("@RolesAllowed(\"X\")")])).should eq([["authenticated"], ["role:X"]])
      strings(JavaAccess.vaadin([written("@RolesAllowed(\"X\")"), written("@AnonymousAllowed")])).should eq([] of Array(String))
      strings(JavaAccess.vaadin([written("@AnonymousAllowed"), written("@DenyAll")])).should eq([["deny"]])
      strings(JavaAccess.vaadin([written("@RolesAllowed(\"**\")")])).should eq([["authenticated"], ["unresolved"]])
      JavaAccess.vaadin([written("@Route(\"x\")")]).should be_nil
    end
  end

  describe ".vertx_handler" do
    {
      {"JWTAuthHandler.create(jwt)", false}                                                                                        => [["authenticated"]],
      {"BasicAuthHandler.create(provider)", true}                                                                                  => [["authenticated"]],
      {"JWTAuthHandler.create(jwt).withScope(\"read\")", false}                                                                    => [["authenticated"], ["unresolved"]],
      {"AuthorizationHandler.create(RoleBasedAuthorization.create(\"admin\"))", false}                                             => [["role:admin"]],
      {"AuthorizationHandler.create(PermissionBasedAuthorization.create(\"posts:write\"))\n  .addAuthorizationProvider(p)", false} => [["permission:posts:write"]],
      {"AuthorizationHandler.create(\n  RoleBasedAuthorization.create(\"admin\"))", false}                                         => [["role:admin"]],
      {"AuthorizationHandler.create(RoleBasedAuthorization.create(role))", false}                                                  => [["unresolved"]],
      {"JWTAuth.create(vertx, config)", false}                                                                                     => [["unresolved"]],
      # Not one of vertx-web's handlers: what it checks is the app's.
      {"AdminAuthHandler.create(\"admin\")", false}                     => [["unresolved"]],
      {"buildAdminGuard()", false}                                      => [["unresolved"]],
      {"new TenantGuard()", false}                                      => [["unresolved"]],
      {"ChainAuthHandler.any().add(JWTAuthHandler.create(jwt))", false} => [["unresolved"]],
      {"BodyHandler.create().setBodyLimit(1024)", false}                => [] of Array(String),
      {"ctx -> ctx.next()", false}                                      => [["unresolved"]],
      # A route's own last handler serves the request, unless it holds a guard the tag reads.
      {"ctx -> ctx.end(\"x\")", true}                                        => [] of Array(String),
      {"ctx -> { if (routingContext.user() == null) ctx.fail(401); }", true} => [["unresolved"]],
    }.each do |(text, last), expected|
      it "reads #{text.lines.first}#{last ? " as the last handler" : ""}" do
        vertx(text, last).should eq(expected)
      end
    end
  end

  describe ".signed_in" do
    it "adds a signed-in clause only when no clause refuses an anonymous caller" do
      unread = [Access::Clause.unresolved("x", "x")]
      JavaAccess.signed_in(unread, "s").map(&.to_s).should eq(["authenticated", "unresolved"])
      roles = [Access::Clause.new([Access::Atom.new(:role, "a")], "s")]
      JavaAccess.signed_in(roles, "s").map(&.to_s).should eq(["role:a"])
    end
  end
end
