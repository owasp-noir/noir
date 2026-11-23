require "../../spec_helper"
require "../../../src/models/access"
require "../../../src/models/endpoint"

private def atom(kind : Access::Kind, value : String? = nil)
  Access::Atom.new(kind, value)
end

describe Access do
  admin = atom(:role, "ADMIN")
  write = atom(:permission, "posts:write")
  signed_in = atom(:authenticated)
  user = atom(:role, "USER")

  describe Access::Atom do
    it "names itself by kind and value" do
      admin.to_s.should eq("role:ADMIN")
      signed_in.to_s.should eq("authenticated")
      atom(:unresolved, "@acl.check(#id)").to_s.should eq("unresolved")
    end
  end

  describe Access::Clause do
    it "sorts and dedups its atoms, so equal sets compare equal" do
      a = Access::Clause.new([write, admin, write], "src")
      b = Access::Clause.new([admin, write], "src")
      a.any_of.should eq([admin, write])
      a.should eq(b)
      [a, b].uniq.size.should eq(1)
    end

    it "refuses an empty clause" do
      expect_raises(ArgumentError) { Access::Clause.new([] of Access::Atom, "src") }
    end

    it "builds an unresolved clause carrying the fragment" do
      clause = Access::Clause.unresolved("#id == 1", "@PreAuthorize(\"#id == 1\")", "A.java", 7)
      clause.any_of.should eq([atom(:unresolved, "#id == 1")])
      {clause.source, clause.path, clause.line}.should eq({"@PreAuthorize(\"#id == 1\")", "A.java", 7})
    end

    it "round-trips through JSON with lowercase kinds and no null keys" do
      clause = Access::Clause.new([write, admin, signed_in], "src", "A.java", 3)
      json = clause.to_json
      json.should eq(%({"any_of":[{"kind":"role","value":"ADMIN"},{"kind":"permission","value":"posts:write"},{"kind":"authenticated"}],"source":"src","path":"A.java","line":3}))
      Access::Clause.from_json(json).should eq(clause)
      Access::Clause.new([admin], "src").to_json.should eq(%({"any_of":[{"kind":"role","value":"ADMIN"}],"source":"src"}))
    end

    it "round-trips through YAML with lowercase kinds" do
      clause = Access::Clause.new([admin, atom(:unresolved, "x")], "src")
      yaml = clause.to_yaml
      yaml.should contain("kind: role")
      yaml.should contain("kind: unresolved")
      yaml.should_not contain("path")
      Access::Clause.from_yaml(yaml).should eq(clause)
    end

    it "canonicalizes a parsed clause" do
      parsed = Access::Clause.from_json(%({"any_of":[{"kind":"permission","value":"w"},{"kind":"role","value":"A"},{"kind":"role","value":"A"}],"source":"s"}))
      parsed.any_of.should eq([atom(:role, "A"), atom(:permission, "w")])
    end
  end

  describe ".both" do
    it "concatenates clauses, with the empty CNF as identity" do
      Access.both([[admin]], [[signed_in]]).should eq([[admin], [signed_in]])
      Access.both(Access::CNF.new, [[admin]]).should eq([[admin]])
    end
  end

  describe ".either" do
    it "distributes OR over the clauses" do
      Access.either([[admin], [signed_in]], [[write]]).should eq([[admin, write], [write, signed_in]])
    end

    it "treats the empty CNF as TRUE" do
      Access.either(Access::CNF.new, [[admin]]).should eq(Access::CNF.new)
      Access.either([[admin]], Access::CNF.new).should eq(Access::CNF.new)
    end
  end

  describe ".clauses" do
    it "stamps every clause with the source and location" do
      clauses = Access.clauses([[admin], [signed_in]], "expr", "A.java", 2)
      clauses.map(&.any_of).should eq([[admin], [signed_in]])
      clauses.all? { |clause| clause.source == "expr" && clause.path == "A.java" && clause.line == 2 }.should be_true
    end

    it "turns an expression over the cap into one unresolved clause" do
      cnf = Array.new(Access::MAX_CLAUSES + 1) { |i| [atom(:role, "R#{i}")] }
      Access.clauses(cnf, "huge").should eq([Access::Clause.unresolved("huge", "huge")])
      Access.clauses(cnf[0, Access::MAX_CLAUSES], "fits").size.should eq(Access::MAX_CLAUSES)
    end
  end

  describe ".cell" do
    anonymous = atom(:anonymous)
    unread = atom(:unresolved, "@acl.check(#id)")

    it "reads each atom kind for each principal" do
      ([
        {anonymous, anonymous, true}, {anonymous, admin, true},
        {atom(:deny), anonymous, false}, {atom(:deny), admin, false},
        {signed_in, anonymous, false}, {signed_in, signed_in, true}, {signed_in, admin, true},
        {admin, admin, true}, {admin, user, false}, {admin, signed_in, false}, {admin, anonymous, false},
        {write, atom(:permission, "posts:write"), true}, {write, atom(:role, "posts:write"), false},
        {unread, anonymous, nil}, {unread, admin, nil},
      ] of {Access::Atom, Access::Atom, Bool?}).each do |required, principal, expected|
        Access.cell([Access::Clause.new([required], "s")], principal).should eq(expected), "#{required} for #{principal}"
      end
    end

    it "holds a clause on any true atom and fails it only when every atom is false" do
      either = Access::Clause.new([admin, unread], "s")
      Access.cell([either], admin).should be_true
      Access.cell([either], user).should be_nil
      Access.cell([Access::Clause.new([admin, write], "s")], user).should be_false
    end

    it "denies on one false clause even when another is unknown" do
      clauses = [Access::Clause.new([unread], "s"), Access::Clause.new([admin], "s")]
      Access.cell(clauses, user).should be_false
      Access.cell(clauses, admin).should be_nil
    end

    it "allows everyone when there is no clause" do
      Access.cell([] of Access::Clause, anonymous).should be_true
    end
  end

  describe ".principals" do
    it "lists anonymous and authenticated, then the held values by kind and value" do
      clauses = [
        Access::Clause.new([atom(:scope, "read"), user, atom(:unresolved, "x")], "s"),
        Access::Clause.new([write, admin, signed_in, atom(:deny)], "s"),
        Access::Clause.new([admin], "s"),
      ]
      Access.principals(clauses).map(&.to_s).should eq(
        %w[anonymous authenticated role:ADMIN role:USER permission:posts:write scope:read])
    end
  end

  describe ".of" do
    admin_clause = Access::Clause.new([admin], "@Secured(\"ROLE_ADMIN\")", "A.java", 4)

    it "reads a tag's own clauses whatever its name" do
      Access.of(Tag.new("auth", "d", "spring_auth", requires: [admin_clause])).should eq([admin_clause])
      denied = Access::Clause.new([atom(:deny)], "denyAll()")
      Access.of(Tag.new("denied", "d", "spring_auth", requires: [denied])).should eq([denied])
    end

    it "reads a guard whose requirement always holds as open to anyone" do
      clauses = Access.of(Tag.new("auth", "Protected by Spring @PreAuthorize", "spring_auth", "A.java", 4, [] of Access::Clause))
      clauses.should eq([Access::Clause.new([atom(:anonymous)], "Protected by Spring @PreAuthorize", "A.java", 4)])
    end

    it "reads an unmigrated guard tag conservatively from its description" do
      Access.of(Tag.new("auth", "Protected by @UseGuards", "nestjs_auth", "a.ts", 9)).should eq([
        Access::Clause.new([signed_in], "Protected by @UseGuards", "a.ts", 9),
        Access::Clause.unresolved("Protected by @UseGuards", "Protected by @UseGuards", "a.ts", 9),
      ])
      Access.of(Tag.new("authz", "Checked by policy", "laravel_auth")).should eq([
        Access::Clause.unresolved("Checked by policy", "Checked by policy"),
      ])
      Access.of(Tag.new("admin", "Admin route", "admin")).should be_empty
    end

    it "ANDs the clauses of every tag on an endpoint, deduped" do
      endpoint = Endpoint.new("/a", "GET")
      endpoint.tags << Tag.new("auth", "d", "spring_auth", requires: [admin_clause])
      endpoint.tags << Tag.new("auth", "d", "spring_security", requires: [admin_clause])
      endpoint.tags << Tag.new("authz", "policy", "other")
      endpoint.tags << Tag.new("admin", "Admin route", "admin")
      Access.of(endpoint).should eq([admin_clause, Access::Clause.unresolved("policy", "policy")])
    end

    it "keeps a guard another layer applies next to a declared anonymous access" do
      open = Access::Clause.new([atom(:anonymous)], "permitAll()", "S.java", 12)
      endpoint = Endpoint.new("/login", "POST")
      endpoint.tags << Tag.new("anonymous", "permitAll()", "spring_auth", "S.java", 12)
      Access.of(endpoint).should eq([open])
      Access.cell(Access.of(endpoint), atom(:anonymous)).should be_true

      endpoint.tags << Tag.new("auth", "d", "spring_auth", requires: [admin_clause])
      Access.of(endpoint).should eq([open, admin_clause])
      Access.cell(Access.of(endpoint), atom(:anonymous)).should be_false
    end

    it "finds nothing on an endpoint without guard tags" do
      Access.of(Endpoint.new("/health", "GET")).should be_empty
    end
  end

  describe ".compare" do
    support = atom(:role, "SUPPORT")
    write_scope = atom(:scope, "w")
    opaque = atom(:unresolved, "@acl.check(#id)")
    other_opaque = atom(:unresolved, "@acl.owns(#id)")
    deny = atom(:deny)
    cnf = ->(clauses : Array(Array(Access::Atom))) { clauses.map { |atoms| Access::Clause.new(atoms, "s") } }

    it "reports old clauses the new requirement no longer implies, strictly or only leniently" do
      none = [] of Array(Access::Atom)
      ([
        {[[admin]], [[admin, support]], [[admin]], none},
        {[[admin], [write_scope]], [[admin]], [[write_scope]], none},
        {[[admin], [opaque]], [[admin]], [[opaque]], none},
        {[[admin]], [[admin, opaque]], [[admin]], none},
        {[[admin]], [[admin], [opaque]], none, none},
        {[[opaque]], [[other_opaque]], none, [[opaque]]},
        {[[opaque], [other_opaque]], [[other_opaque]], [[opaque]], none},
        {[[signed_in], [opaque], [other_opaque]], [[signed_in], [opaque]], [[other_opaque]], none},
        {[[opaque]], [[opaque, other_opaque]], [[opaque]], none},
        {[[opaque], [other_opaque]], [[atom(:unresolved, "x")], [atom(:unresolved, "y")]], none, [[opaque], [other_opaque]]},
        {[[signed_in], [opaque]], none, [[signed_in], [opaque]], none},
        {[[signed_in]], [[admin]], none, none},
        {[[admin]], [[signed_in]], [[admin]], none},
        {[[admin], [opaque]], [[deny]], none, none},
        {[[deny]], [[admin]], [[deny]], none},
        {[[atom(:anonymous)]], none, none, none},
        {[[atom(:anonymous), admin]], [[support]], none, none},
      ] of {Array(Array(Access::Atom)), Array(Array(Access::Atom)), Array(Array(Access::Atom)), Array(Array(Access::Atom))}).each do |old, new, widened, unverified|
        change = Access.compare(cnf.call(old), cnf.call(new))
        change.widened.map(&.any_of).should eq(widened), "widened for #{old} -> #{new}"
        change.unverified.map(&.any_of).should eq(unverified), "unverified for #{old} -> #{new}"
        change.empty?.should eq(widened.empty? && unverified.empty?)
      end
    end

    it "ignores where a clause was declared, so a moved annotation is no change" do
      old = [Access::Clause.new([admin], "@Secured(\"ROLE_ADMIN\")", "A.java", 4)]
      moved = [Access::Clause.new([admin], "@Secured({\"ROLE_ADMIN\"})", "B.java", 40)]
      Access.compare(old, moved).empty?.should be_true
    end

    it "names a clause by its atoms, parenthesized when there are several" do
      Access::Clause.new([user, admin], "s").to_s.should eq("(role:ADMIN | role:USER)")
      Access::Clause.new([opaque], "s").to_s.should eq("unresolved")
    end

    it "keeps the old clause's source and location for the reviewer" do
      lost = Access::Clause.new([admin], "hasRole('ADMIN')", "A.java", 4)
      Access.compare([lost], [] of Access::Clause).widened.should eq([lost])
    end
  end
end

describe "Access.parse_atom" do
  it "splits at the first colon and canonicalizes the kind" do
    Access.parse_atom("role:ADMIN").should eq(Access::Atom.new(:role, "ADMIN"))
    Access.parse_atom("Permission:posts:write").should eq(Access::Atom.new(:permission, "posts:write"))
    Access.parse_atom("scope:read:pets").to_s.should eq("scope:read:pets")
    Access.parse_atom("authenticated").should eq(Access::Atom.new(:authenticated))
    Access.parse_atom("unresolved").to_s.should eq("unresolved")
    Access.parse_atom(" role: ADMIN ").should eq(Access::Atom.new(:role, "ADMIN"))
  end

  it "rejects an unknown kind, a missing value, and a value on a bare kind" do
    {
      "rol:ADMIN"         => "unknown kind rol. Valid: role, permission, scope, authenticated, anonymous, deny, unresolved",
      "r_o_l_e:ADMIN"     => "unknown kind r_o_l_e.",
      ":ADMIN"            => "unknown kind (none).",
      "role"              => "role needs a value (role:<value>)",
      "scope:"            => "scope needs a value (scope:<value>)",
      "authenticated:yes" => "authenticated takes no value",
      "unresolved:x"      => "unresolved takes no value",
    }.each do |text, message|
      expect_raises(ArgumentError, message) { Access.parse_atom(text) }
    end
  end
end
