require "../../../spec_helper"
require "../../../../src/tagger/framework_taggers/python/fastapi_access"

private def strings(cnf : Access::CNF) : Array(Array(String))
  cnf.map(&.sort.map(&.to_s))
end

describe FastAPIAccess do
  describe ".scheme" do
    {
      %w[]                                   => [["authenticated"]],
      [%q(tokenUrl="token")]                 => [["authenticated"]],
      %w[auto_error=True]                    => [["authenticated"]],
      %w[auto_error=False]                   => [["unresolved"]],
      %w[auto_error=settings.strict]         => [["unresolved"]],
      [%q(name="X-Key"), "auto_error=False"] => [["unresolved"]],
      %w[**options]                          => [["unresolved"]],
      # `OAuth2PasswordBearer(tokenUrl, scheme_name, scopes, description, auto_error)`.
      %w[url None None None False] => [["unresolved"]],
      %w[url None None None]       => [["authenticated"]],
    }.each do |args, expected|
      it "reads (#{args.join(", ")})" do
        strings(FastAPIAccess.scheme(args, "HTTPBearer(...)")).should eq(expected)
      end
    end

    it "keeps the declaration text of a scheme it cannot settle" do
      FastAPIAccess.scheme(%w[auto_error=False], "Depends(soft)").flatten.map(&.value).should eq(["Depends(soft)"])
    end

    it "knows FastAPI's scheme classes by name" do
      FastAPIAccess.scheme?("fastapi.security.HTTPBasic").should be_true
      FastAPIAccess.scheme?("APIKeyCookie").should be_true
      FastAPIAccess.scheme?("SecurityScopes").should be_false
    end
  end

  describe ".scope_atoms" do
    {
      %q(["items:read", 'items:write']) => ["scope:items:read", "scope:items:write"],
      %q(("me",))                       => ["scope:me"],
      %q(["me", EXTRA])                 => ["scope:me", "unresolved"],
      %q(SCOPES)                        => ["unresolved"],
      %q([f"{prefix}:read"])            => ["unresolved"],
      %q([])                            => [] of String,
    }.each do |value, expected|
      it "reads #{value}" do
        FastAPIAccess.scope_atoms(value).map(&.to_s).should eq(expected)
      end
    end
  end

  describe ".checks_every_scope?" do
    documented = <<-PY
      async def get_current_user(security_scopes: SecurityScopes, token: str = Depends(oauth2_scheme)):
          for scope in security_scopes.scopes:
              if scope not in token_data.scopes:
                  raise credentials_exception
      PY
    inline = <<-PY
      def user(scopes: SecurityScopes):
          for s in scopes.scopes:
              if s not in granted(): raise HTTPException(401)
      PY
    subset = <<-PY
      def user(security_scopes: SecurityScopes):
          if not set(security_scopes.scopes) <= granted():
              raise HTTPException(401)
      PY
    logged = <<-PY
      def user(security_scopes: SecurityScopes):
          for scope in security_scopes.scopes:
              if scope not in granted():
                  log(scope)
      PY
    untyped = <<-PY
      def user(security_scopes):
          for scope in security_scopes.scopes:
              if scope not in granted():
                  raise HTTPException(401)
      PY

    it "reads the documented loop" do
      FastAPIAccess.checks_every_scope?(documented).should be_true
      FastAPIAccess.checks_every_scope?(inline).should be_true
    end

    it "does not take another spelling, a loop that does not refuse, or an untyped parameter" do
      FastAPIAccess.checks_every_scope?(subset).should be_false
      FastAPIAccess.checks_every_scope?(logged).should be_false
      FastAPIAccess.checks_every_scope?(untyped).should be_false
    end
  end

  describe ".role_comparison" do
    {
      %q(user.role != role)                     => {"user", "role", false},
      %q(current_user.role not in self.allowed) => {"current_user", "self.allowed", true},
      %q("admin" not in user.roles)             => {"user", %q("admin"), false},
      %q(user.role == "admin")                  => nil,
      %q(user.role != "a" and user.active)      => nil,
      %q(not user.role == "admin")              => nil,
      %q(user.is_superuser)                     => nil,
      %q(user.roles not in ALLOWED)             => nil,
    }.each do |cond, expected|
      it "reads #{cond}" do
        FastAPIAccess.role_comparison(cond).should eq(expected)
      end
    end
  end

  describe ".role_atoms" do
    {
      { %q("admin"), false }               => ["role:admin"],
      { %q(["admin", 'editor']), true }    => ["role:admin", "role:editor"],
      { %q(("admin", Role.EDITOR)), true } => ["role:admin", "unresolved"],
      { %q("admin"), true }                => ["unresolved"],
      { %q([]), true }                     => ["unresolved"],
      { %q(Role.ADMIN), false }            => ["unresolved"],
      { %q(f"{x}"), false }                => ["unresolved"],
    }.each do |(value, collection), expected|
      it "reads #{value}#{" as a collection" if collection}" do
        FastAPIAccess.role_atoms(value, "ref", collection).map(&.to_s).should eq(expected)
      end
    end

    it "keeps the reference of a value it could not read" do
      FastAPIAccess.role_atoms(nil, "self.allowed", true).map(&.value).should eq(["self.allowed"])
    end
  end

  describe ".absence_test?" do
    {
      "not user"               => true,
      "token is None"          => true,
      "  current_user == None" => true,
      "not settings.enabled"   => false,
      "user.id is None"        => false,
      "not user or user.ban"   => false,
    }.each do |cond, expected|
      it "reads #{cond.strip}" do
        FastAPIAccess.absence_test?(cond).should eq(expected)
      end
    end
  end

  it "lifts each clause with the setting" do
    lifted = FastAPIAccess.liftable([[FastAPIAccess::AUTHENTICATED], [Access::Atom.new(:scope, "x")]], "flag")
    strings(lifted).should eq([["authenticated", "unresolved"], ["scope:x", "unresolved"]])
  end
end
