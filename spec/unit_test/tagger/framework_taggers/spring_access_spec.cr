require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/java/spring_access"

private def read(expression : String) : Array(Array(String))
  SpringAccess.expression(expression).map(&.sort.map(&.to_s))
end

private def read_annotation(name : String, arg : String?) : Array(Array(String))
  SpringAccess.annotation(name, arg).map(&.sort.map(&.to_s))
end

private def unresolved_values(cnf : Access::CNF) : Array(String?)
  cnf.flatten.select(&.kind.unresolved?).map(&.value)
end

describe SpringAccess do
  describe ".expression" do
    {
      "hasRole('ADMIN')"                                     => [["role:ADMIN"]],
      "hasRole('ROLE_ADMIN')"                                => [["role:ADMIN"]],
      "hasAnyRole('ADMIN', \"USER\")"                        => [["role:ADMIN", "role:USER"]],
      "hasAuthority('ROLE_ADMIN')"                           => [["role:ADMIN"]],
      "hasAuthority('SCOPE_read')"                           => [["scope:read"]],
      "hasAnyAuthority('posts:write', 'SCOPE_write')"        => [["permission:posts:write", "scope:write"]],
      "isAuthenticated()"                                    => [["authenticated"]],
      "isFullyAuthenticated()"                               => [["authenticated"]],
      "authenticated()"                                      => [["authenticated"]],
      "authenticated"                                        => [["authenticated"]],
      "fullyAuthenticated"                                   => [["authenticated"]],
      "denyAll()"                                            => [["deny"]],
      "denyAll"                                              => [["deny"]],
      "isAnonymous()"                                        => [["anonymous"]],
      "hasRole('ANONYMOUS')"                                 => [["anonymous"]],
      "permitAll()"                                          => [] of Array(String),
      "hasRole('A') and hasRole('B')"                        => [["role:A"], ["role:B"]],
      "hasRole('A') && isAuthenticated()"                    => [["role:A"], ["authenticated"]],
      "hasRole('A') or hasAuthority('posts:write')"          => [["role:A", "permission:posts:write"]],
      "hasRole('A') || hasRole('B')"                         => [["role:A", "role:B"]],
      "hasRole('A') OR hasRole('B')"                         => [["role:A", "role:B"]],
      "(hasRole('A') or hasRole('B')) and isAuthenticated()" => [["role:A", "role:B"], ["authenticated"]],
      "hasRole('A') and (hasRole('B') or hasRole('C'))"      => [["role:A"], ["role:B", "role:C"]],
      "(hasRole('A') and hasRole('B')) or hasRole('C')"      => [["role:A", "role:C"], ["role:B", "role:C"]],
      "permitAll() or hasRole('A')"                          => [] of Array(String),
      "hasRole('order') or hasRole('android')"               => [["role:android", "role:order"]],
      "access(\"hasRole('A')\")"                             => [["role:A"]],
    }.each do |expression, expected|
      it "reads #{expression}" do
        read(expression).should eq(expected)
      end
    end

    {
      "@acl.canEdit(#id)"                  => "@acl.canEdit(#id)",
      "#owner == authentication.name"      => "#owner == authentication.name",
      "principal.enabled"                  => "principal.enabled",
      "!isAnonymous()"                     => "!isAnonymous()",
      "not hasRole('A')"                   => "not hasRole('A')",
      "hasPermission(#id, 'read')"         => "hasPermission(#id, 'read')",
      "isRememberMe()"                     => "isRememberMe()",
      "access((auth, ctx) -> check(auth))" => "access((auth, ctx) -> check(auth))",
    }.each do |expression, fragment|
      it "keeps #{expression} as an unresolved atom" do
        SpringAccess.expression(expression).should eq([[Access::Atom.new(:unresolved, fragment)]])
      end
    end

    it "keeps a non-literal argument as an unresolved atom beside the literal ones" do
      read("hasAnyRole('A', Roles.ADMIN)").should eq([["role:A", "unresolved"]])
      unresolved_values(SpringAccess.expression("hasAnyRole('A', Roles.ADMIN)")).should eq(["Roles.ADMIN"])
    end

    it "keeps an unreadable operand in its own clause, so the AND still holds" do
      cnf = SpringAccess.expression("hasRole('A') and @acl.check(#id)")
      cnf.map(&.map(&.to_s)).should eq([["role:A"], ["unresolved"]])
      unresolved_values(cnf).should eq(["@acl.check(#id)"])
    end

    it "reads text that is not one whole expression as a single unresolved atom" do
      ["hasRole('A') and", "hasRole('A') or (hasRole('B')", "hasRole('A')) or hasRole('B')", "hasRole('A'"].each do |broken|
        SpringAccess.expression(broken).should eq([[Access::Atom.new(:unresolved, broken)]])
      end
    end

    it "leaves an expression whose OR expands past the cap unresolved" do
      text = (1..4).map { |i| "(hasRole('A#{i}') and hasRole('B#{i}'))" }.join(" or ")
      SpringAccess.expression(text).should eq([[Access::Atom.new(:unresolved, text)]])
    end
  end

  describe ".annotation" do
    it "reads @PreAuthorize and @PostAuthorize through the expression reader" do
      read_annotation("PreAuthorize", "\"hasRole('ADMIN') or hasAuthority('posts:write')\"").should eq([["role:ADMIN", "permission:posts:write"]])
      read_annotation("PostAuthorize", "value = \"isAuthenticated()\"").should eq([["authenticated"]])
      read_annotation("PreAuthorize", "\"hasRole(\\\"ADMIN\\\")\"").should eq([["role:ADMIN"]])
    end

    it "keeps a concatenated or constant expression unresolved" do
      SpringAccess.annotation("PreAuthorize", "\"hasRole('\" + Roles.ADMIN + \"')\"").should eq([[Access::Atom.new(:unresolved, "@PreAuthorize(\"hasRole('\" + Roles.ADMIN + \"')\")")]])
      SpringAccess.annotation("PreAuthorize", "Expressions.ADMIN").should eq([[Access::Atom.new(:unresolved, "@PreAuthorize(Expressions.ADMIN)")]])
    end

    it "reads @Secured authorities" do
      read_annotation("Secured", "\"ROLE_USER\"").should eq([["role:USER"]])
      read_annotation("Secured", "{\"ROLE_ADMIN\", \"SCOPE_read\", \"audit\"}").should eq([["role:ADMIN", "permission:audit", "scope:read"]])
      read_annotation("Secured", "\"IS_AUTHENTICATED_FULLY\"").should eq([["authenticated"]])
      read_annotation("Secured", "\"IS_AUTHENTICATED_REMEMBERED\"").should eq([["authenticated"]])
    end

    it "reads @Secured(IS_AUTHENTICATED_ANONYMOUSLY) as admitting anyone" do
      read_annotation("Secured", "\"IS_AUTHENTICATED_ANONYMOUSLY\"").should eq([] of Array(String))
      read_annotation("Secured", "{\"ROLE_USER\", \"IS_AUTHENTICATED_ANONYMOUSLY\"}").should eq([] of Array(String))
    end

    it "reads @RolesAllowed roles, stripping one ROLE_ prefix" do
      read_annotation("RolesAllowed", "{\"ROLE_ADMIN\", \"MANAGER\"}").should eq([["role:ADMIN", "role:MANAGER"]])
      read_annotation("RolesAllowed", "[\"ADMIN\"]").should eq([["role:ADMIN"]])
      read_annotation("RolesAllowed", "{Roles.ADMIN}").should eq([["unresolved"]])
    end

    it "reads @PermitAll and @DenyAll" do
      read_annotation("PermitAll", nil).should eq([] of Array(String))
      read_annotation("DenyAll", nil).should eq([["deny"]])
    end

    it "leaves annotations outside Spring's vocabulary unresolved" do
      SpringAccess.annotation("RequiresRoles", "\"admin\"").should eq([[Access::Atom.new(:unresolved, "@RequiresRoles(\"admin\")")]])
      SpringAccess.annotation("RequiresAuthentication", nil).should eq([[Access::Atom.new(:unresolved, "@RequiresAuthentication")]])
    end
  end
end
