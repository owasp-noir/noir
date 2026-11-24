require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/csharp/aspnet_access"

private def shown(cnf : Access::CNF) : Array(Array(String))
  cnf.map(&.sort.map(&.to_s))
end

private def unresolved_values(cnf : Access::CNF) : Array(String?)
  cnf.flatten.select(&.kind.unresolved?).map(&.value)
end

describe AspnetAccess do
  describe ".authorize" do
    {
      nil                                               => [["authenticated"]],
      %(Roles = "Admin,Manager")                        => [["role:Admin", "role:Manager"]],
      %(Roles = " Admin , ")                            => [["role:Admin"]],
      %(Roles = @"Admin")                               => [["role:Admin"]],
      %(AuthenticationSchemes = "Bearer")               => [["authenticated"]],
      %(Roles = "A", Policy = "P")                      => [["role:A"], ["unresolved"]],
      %(Policy = "P", AuthenticationSchemes = "Bearer") => [["unresolved"]],
    }.each do |args, expected|
      it "reads [Authorize(#{args})]" do
        shown(AspnetAccess.authorize(args)).should eq(expected)
      end
    end

    {
      %(Policy = "CanExport") => "Policy=CanExport",
      %("CanExport")          => "Policy=CanExport",
      %(policy: "CanExport")  => "Policy=CanExport",
    }.each do |args, value|
      it "keeps the named policy of [Authorize(#{args})] unread" do
        cnf = AspnetAccess.authorize(args)
        shown(cnf).should eq([["unresolved"]])
        unresolved_values(cnf).should eq([value])
      end
    end

    {
      %(Roles = RoleNames.Admin)  => "Roles = RoleNames.Admin",
      %(Roles = nameof(Admin))    => "Roles = nameof(Admin)",
      %(Roles = "A" + Extra)      => %(Roles = "A" + Extra),
      %(Roles = $"{Prefix}Admin") => %(Roles = $"{Prefix}Admin"),
      %(Roles = "")               => %(Roles = ""),
      %(Policy = Policies.Admin)  => "Policies.Admin",
    }.each do |args, value|
      it "keeps the non-literal #{args} unresolved" do
        cnf = AspnetAccess.authorize(args)
        shown(cnf).should eq([["unresolved"]])
        unresolved_values(cnf).should eq([value])
      end
    end

    it "takes the default policy it is given for a bare [Authorize]" do
      default = [[Access::Atom.new(:unresolved, "DefaultPolicy = custom")]]
      AspnetAccess.authorize(nil, default).should eq(default)
      shown(AspnetAccess.authorize(%(Roles = "A"), default)).should eq([["role:A"]])
    end
  end

  describe ".default_policy_assignment" do
    it "reads the assignment without the call around it" do
      code = %(services.AddAuthorization(o => o.DefaultPolicy = new AuthorizationPolicyBuilder().RequireClaim("t").Build());)
      AspnetAccess.default_policy_assignment(code).should eq(%(DefaultPolicy = new AuthorizationPolicyBuilder().RequireClaim("t").Build()))
      AspnetAccess.default_policy_assignment(%(builder.Services.AddAuthorizationBuilder()\n    .SetDefaultPolicy(new AuthorizationPolicyBuilder().RequireRole("Admin").Build());)).should eq(%(SetDefaultPolicy(new AuthorizationPolicyBuilder().RequireRole("Admin").Build())))
      AspnetAccess.default_policy_assignment("public Task<AuthorizationPolicy> GetDefaultPolicyAsync() =>\n    Task.FromResult(policy);").should eq("GetDefaultPolicyAsync() of a custom IAuthorizationPolicyProvider")
      AspnetAccess.default_policy_assignment("var p = await _fallback.GetDefaultPolicyAsync();").should be_nil
      AspnetAccess.default_policy_assignment("var p = options.DefaultPolicy;").should be_nil
      AspnetAccess.default_policy_assignment("if (o.DefaultPolicy == null) { }").should be_nil
    end
  end

  describe ".require_authorization" do
    {
      ""                                                               => [["authenticated"]],
      %("A", "B")                                                      => [["unresolved"], ["unresolved"]],
      %(new AuthorizeAttribute { Roles = "Admin" })                    => [["role:Admin"]],
      %(new AuthorizeAttribute())                                      => [["authenticated"]],
      %(new AuthorizeAttribute("P"))                                   => [["unresolved"]],
      %(p => p.RequireRole("Admin", "Ops").RequireAuthenticatedUser()) => [["role:Admin", "role:Ops"], ["authenticated"]],
      %(policy => policy.RequireClaim("scope", "api"))                 => [["unresolved"]],
      %(p => p.RequireRole("A").RequireAssertion(c => true))           => [["role:A"], ["unresolved"]],
      %(p => { p.RequireRole("A"); })                                  => [["unresolved"]],
      %(new AuthorizationPolicyBuilder().RequireRole("BR").Build())    => [["role:BR"]],
      "adminPolicy"                                                    => [["unresolved"]],
      "Policies.Admin"                                                 => [["unresolved"]],
    }.each do |args, expected|
      it "reads .RequireAuthorization(#{args})" do
        shown(AspnetAccess.require_authorization(args)).should eq(expected)
      end
    end

    it "keeps each policy name" do
      unresolved_values(AspnetAccess.require_authorization(%("A", "B"))).should eq(["Policy=A", "Policy=B"])
    end
  end

  describe ".policy" do
    {
      "new AuthorizationPolicyBuilder().RequireAuthenticatedUser().Build()"            => [["authenticated"]],
      %(new AuthorizationPolicyBuilder("Bearer").RequireRole("A").Build())             => [["role:A"]],
      %(new AuthorizationPolicyBuilder().AddAuthenticationSchemes("x").Build())        => [["unresolved"]],
      %(new AuthorizationPolicyBuilder().RequireRole(Roles.Admin).Build())             => [["unresolved"]],
      %(new AuthorizationPolicyBuilder().RequireRole("A") + extra)                     => [["unresolved"]],
      "new AuthorizationPolicyBuilder().RequireRole(\"a)b\").RequireUserName(\"bob\")" => [["role:a)b"], ["unresolved"]],
      "existingPolicy"                                                                 => [["unresolved"]],
    }.each do |text, expected|
      it "reads #{text}" do
        shown(AspnetAccess.policy(text)).should eq(expected)
      end
    end

    it "keeps the text of a requirement it does not read" do
      unresolved_values(AspnetAccess.policy(%(p.RequireRole("A").RequireClaim("dept", "x")), "p")).should eq([%(RequireClaim("dept", "x"))])
    end
  end

  describe ".fastendpoints" do
    {
      %(Get("/x");)                                   => [["authenticated"]],
      %(// Roles("Admin");\nGet("/x");)               => [["authenticated"]],
      %(Roles("Admin", "Manager");)                   => [["authenticated"], ["role:Admin", "role:Manager"]],
      %(Roles("A");\nRoles("B");)                     => [["authenticated"], ["role:A", "role:B"]],
      %(Permissions("a", "b");)                       => [["authenticated"], ["permission:a", "permission:b"]],
      %(PermissionsAll("a", "b");)                    => [["authenticated"], ["permission:a"], ["permission:b"]],
      %(Permissions("a");\nPermissionsAll("b");)      => [["authenticated"], ["permission:a"], ["permission:b"]],
      %(PermissionsAll("a");\nPermissions("b");)      => [["authenticated"], ["permission:a", "permission:b"]],
      %(Scopes("read", "write");)                     => [["authenticated"], ["scope:read", "scope:write"]],
      %(ScopesAll("read", "write");)                  => [["authenticated"], ["scope:read"], ["scope:write"]],
      %(Claims("EmployeeID", "Dept");)                => [["authenticated"], ["unresolved", "unresolved"]],
      %(ClaimsAll("EmployeeID", "Dept");)             => [["authenticated"], ["unresolved"], ["unresolved"]],
      %(Policies("X", "Y");)                          => [["authenticated"], ["unresolved"], ["unresolved"]],
      %(Policy(b => b.RequireRole("Ops"));)           => [["authenticated"], ["role:Ops"]],
      %(Policy(ConfigurePolicy);)                     => [["authenticated"], ["unresolved"]],
      %(Roles(Role.Admin, "Ops");)                    => [["authenticated"], ["role:Ops", "unresolved"]],
      %(Roles("Admin");\nPermissions("posts:write");) => [["authenticated"], ["role:Admin"], ["permission:posts:write"]],
      %(Group<AdminGroup>();)                         => [["authenticated"], ["unresolved"]],
      %(Options(x => x.RequireAuthorization("P"));)   => [["authenticated"], ["unresolved"]],
      %(Roles();)                                     => [["authenticated"]],
    }.each do |block, expected|
      it "reads #{block.inspect}" do
        shown(AspnetAccess.fastendpoints(block)).should eq(expected)
      end
    end

    it "takes the default policy for an endpoint that names no requirement" do
      custom = [[Access::Atom.new(:unresolved, "DefaultPolicy = custom")]]
      AspnetAccess.fastendpoints(%(Get("/x");), custom).should eq(custom)
      shown(AspnetAccess.fastendpoints(%(AuthSchemes("Bearer");), custom)).should eq([["authenticated"]])
      shown(AspnetAccess.fastendpoints(%(Policies("X");), custom)).should eq([["authenticated"], ["unresolved"]])
    end

    it "keeps claim types and policy names" do
      unresolved_values(AspnetAccess.fastendpoints(%(Claims("EmployeeID");\nPolicies("X");))).should eq([%(Policy=X), "claim type EmployeeID"])
    end
  end
end
