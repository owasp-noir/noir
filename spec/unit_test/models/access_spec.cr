require "../../spec_helper"
require "../../../src/models/access"

private def atom(kind : Access::Kind, value : String? = nil)
  Access::Atom.new(kind, value)
end

describe Access do
  admin = atom(:role, "ADMIN")
  write = atom(:permission, "posts:write")
  signed_in = atom(:authenticated)

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
end
