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

    it "lets an anonymous tag override every guard tag" do
      endpoint = Endpoint.new("/login", "POST")
      endpoint.tags << Tag.new("auth", "d", "spring_auth", requires: [admin_clause])
      endpoint.tags << Tag.new("anonymous", "permitAll()", "spring_auth", "S.java", 12)
      Access.of(endpoint).should eq([Access::Clause.new([atom(:anonymous)], "permitAll()", "S.java", 12)])
    end

    it "finds nothing on an endpoint without guard tags" do
      Access.of(Endpoint.new("/health", "GET")).should be_empty
    end
  end
end
