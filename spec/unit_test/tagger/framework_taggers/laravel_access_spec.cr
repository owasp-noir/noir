require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/php/laravel_access"

private def read(cnf : Access::CNF?) : Array(Array(String))?
  cnf.try &.map(&.sort.map(&.to_s))
end

private SPATIE_ROLE       = "Spatie\\Permission\\Middleware\\RoleMiddleware"
private SPATIE_PERMISSION = "\\Spatie\\Permission\\Middlewares\\PermissionMiddleware"
private SANCTUM_ALL       = "Laravel\\Sanctum\\Http\\Middleware\\CheckAbilities"
private SANCTUM_ANY       = "Laravel\\Sanctum\\Http\\Middleware\\CheckForAnyAbility"
private PASSPORT_ALL      = "Laravel\\Passport\\Http\\Middleware\\CheckToken"
private PASSPORT_ANY      = "Laravel\\Passport\\Http\\Middleware\\CheckForAnyScope"

describe LaravelAccess do
  describe ".middleware" do
    {
      {"auth", nil}                                                                                   => [["authenticated"]],
      {"auth:api", nil}                                                                               => [["authenticated"]],
      {"auth:sanctum,web", nil}                                                                       => [["authenticated"]],
      {"auth.basic", nil}                                                                             => [["authenticated"]],
      {"guest", nil}                                                                                  => [["unresolved"]],
      {"can:update,post", nil}                                                                        => [["permission:update"]],
      {"can:viewAny", nil}                                                                            => [["permission:viewAny"]],
      {"can:a|b", nil}                                                                                => [["unresolved"]],
      {"can:", nil}                                                                                   => [["unresolved"]],
      {"role:admin|editor", SPATIE_ROLE}                                                              => [["role:admin", "role:editor"]],
      {"role:admin,api", SPATIE_ROLE}                                                                 => [["role:admin"]],
      {"permission:edit articles|delete articles", SPATIE_PERMISSION}                                 => [["permission:delete articles", "permission:edit articles"]],
      {"permission:posts.*", SPATIE_PERMISSION}                                                       => [["unresolved"]],
      {"role_or_permission:admin|edit", "Spatie\\Permission\\Middleware\\RoleOrPermissionMiddleware"} => [["unresolved"]],
      {"role:", SPATIE_ROLE}                                                                          => [["unresolved"]],
      {"abilities:read,write", SANCTUM_ALL}                                                           => [["scope:read"], ["scope:write"]],
      {"ability:read,write", SANCTUM_ANY}                                                             => [["scope:read", "scope:write"]],
      {"scopes:a,b", PASSPORT_ALL}                                                                    => [["scope:a"], ["scope:b"]],
      {"scope:a,b", PASSPORT_ANY}                                                                     => [["scope:a", "scope:b"]],
      {"role:admin", nil}                                                                             => [["unresolved"]],
      {"abilities:read", nil}                                                                         => [["unresolved"]],
    }.each do |(entry, klass), expected|
      it "reads #{entry} (#{klass || "no alias class"})" do
        read(LaravelAccess.middleware(entry, klass)).should eq(expected)
      end
    end

    {
      {"verified", nil},
      {"throttle:60,1", nil},
      {"signed", nil},
      {"password.confirm", nil},
      {"web", nil},
      {"role:admin", "App\\Http\\Middleware\\CheckRole"},
    }.each do |(entry, klass)|
      it "does not read #{entry} as a requirement" do
        LaravelAccess.middleware(entry, klass).should be_nil
      end
    end

    it "keeps the unread text" do
      cnf = LaravelAccess.middleware("role_or_permission:admin|edit", "Spatie\\Permission\\Middleware\\RoleOrPermissionMiddleware").should_not be_nil
      cnf.flatten.map(&.value).should eq(["role_or_permission:admin|edit"])
      LaravelAccess.middleware("guest:web").should eq([[Access::Atom.new(:unresolved, "guest:web")]])
    end
  end

  describe ".gate_call" do
    {
      "$this->authorize('update', $post)"      => [["permission:update"]],
      "$this->authorize( \"view\", $post )"    => [["permission:view"]],
      "Gate::authorize('create', Post::class)" => [["permission:create"]],
      "$this->authorize('update')"             => [["permission:update"]],
      "$this->authorize($ability, $post)"      => [["unresolved"]],
      "$this->authorize(\"edit-$kind\")"       => [["unresolved"]],
      "Gate::authorize(Ability::Edit)"         => [["unresolved"]],
      "$this->authorize($post)"                => [["unresolved"]],
    }.each do |call, expected|
      it "reads #{call}" do
        read(LaravelAccess.gate_call(call)).should eq(expected)
      end
    end
  end

  it "adds the note to every clause as an alternative" do
    clauses = [Access::Clause.new([Access::Atom.new(:authenticated)], "auth")]
    lifted = LaravelAccess.liftable(clauses, "a condition decides")
    lifted.map(&.any_of).should eq([[Access::Atom.new(:authenticated), Access::Atom.new(:unresolved, "a condition decides")]])
    lifted[0].source.should eq("auth")
  end
end
