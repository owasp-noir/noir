require "../../spec_helper"
require "../../../src/miniparsers/huma_security"

describe HumaSecurity do
  it "reads each entry's scheme and scopes, keeping what is not a literal as text" do
    {
      %({"bearer": {}})                  => {"bearer" => [] of String},
      %({"oauth": {"read", "write"}})    => {"oauth" => ["read", "write"]},
      %({"oauth": []string{"read"}})     => {"oauth" => ["read"]},
      %({"key": nil})                    => {"key" => [] of String},
      %({"a": {}, "b": {"s"}})           => {"a" => [] of String, "b" => ["s"]},
      %({"oauth": scopes})               => {"oauth" => "scopes"},
      %({"oauth": {"read", other}})      => {"oauth" => %({"read", other})},
      %({"oauth": {"a\\"b"}})            => {"oauth" => %({"a\\"b"})},
      %({"a": {}, schemeB: {}})          => {"a" => [] of String, "schemeB" => "schemeB: {}"},
      %({auth.Scheme: {"read"}})         => {"auth.Scheme" => %(auth.Scheme: {"read"})},
      %({"oauth": {"read"}, f(): {"x"}}) => {"oauth" => ["read"], %(f(): {"x"}) => %(f(): {"x"})},
    }.each do |alternative, expected|
      HumaSecurity.requirement(alternative).should eq(expected)
    end
  end

  it "keeps an entry it cannot name a credential requirement" do
    requirement = HumaSecurity.requirement(%({"a": {}, schemeB: {}}))
    clauses = Access.clauses(OasSecurityAccess.cnf([requirement], nil, "huma"), "huma")
    clauses.map(&.to_s).should eq ["authenticated", "unresolved"]
    Access.cell(clauses, Access::Atom.new(:anonymous)).should be_false
  end
end
