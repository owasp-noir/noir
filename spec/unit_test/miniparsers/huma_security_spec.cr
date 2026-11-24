require "../../spec_helper"
require "../../../src/miniparsers/huma_security"

private def shown(cnf : Access::CNF?) : Array(String)?
  cnf.try &.map(&.join(" | ") { |atom| atom.value ? "#{atom.kind.to_s.downcase}:#{atom.value}" : atom.kind.to_s.downcase })
end

describe HumaSecurity do
  it "reads each scheme as a credential plus its unread check, and literal scopes as scopes" do
    {
      %([]map[string][]string{{"bearer": {}}})            => ["authenticated", "unresolved:bearer"],
      %([]map[string][]string{{"o": {"read", "write"}}})  => ["authenticated", "unresolved:o", "scope:read", "scope:write"],
      %([]map[string][]string{{"o": []string{"read"}}})   => ["authenticated", "unresolved:o", "scope:read"],
      %([]map[string][]string{{"key": nil}})              => ["authenticated", "unresolved:key"],
      %([]map[string][]string{{"a": {}, "b": {}}})        => ["authenticated", "unresolved:a", "unresolved:b"],
      %([]map[string][]string{{"o": scopes}})             => ["authenticated", "unresolved:o", "unresolved:o: scopes"],
      %([]map[string][]string{{"o": {"a\\"b"}}})          => ["authenticated", "unresolved:o", %(unresolved:o: {"a\\"b"})],
      %([]map[string][]string{{"o": {""}}})               => ["authenticated", "unresolved:o", %(unresolved:o: {""})],
      %([]map[string][]string{{SchemeName: {"admin"}}})   => ["authenticated", %(unresolved:SchemeName: {"admin"})],
      %([]map[string][]string{{`ra{w`: {}}})              => ["authenticated", "unresolved:`ra{w`: {}"],
      %([]map[string][]string{{"a}b": {}}})               => ["authenticated", "unresolved:a}b"],
      %([]map[string][]string{{a: {}, "a": {}}})          => ["authenticated", "unresolved:a: {}", "unresolved:a"],
      %([]map[string][]string{{"o": {"a,b"}}})            => ["authenticated", "unresolved:o", "scope:a,b"],
      %([]map[string][]string{{"o": { // why\n "read"}}}) => ["authenticated", "unresolved:o", "scope:read"],
      %([]map[string][]string{{"a": {}}, {"b": {}}})      => ["authenticated", "authenticated | unresolved:b", "authenticated | unresolved:a", "unresolved:a | unresolved:b"],
      %([]map[string][]string{{"key": {}}, openAlt})      => ["authenticated | unresolved:openAlt", "unresolved:key | unresolved:openAlt"],
      %([]map[string][]string{openAlt})                   => ["unresolved:openAlt"],
    }.each do |literal, expected|
      shown(HumaSecurity.cnf(literal)).should eq(expected)
    end
  end

  it "reads an empty list, an empty alternative or a commented-out entry as open" do
    HumaSecurity.cnf(%([]map[string][]string{})).should be_nil
    HumaSecurity.cnf(%([]map[string][]string{{"a": {}}, {}})).should be_nil
    HumaSecurity.cnf(%([]map[string][]string{{\n// "admin": {"root"},\n}})).should be_nil
  end
end
