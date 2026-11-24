require "../../spec_helper"
require "../../../src/analyzer/engines/oas_security_access"

private SCHEMES = {
  "oauth"  => "oauth2",
  "oidc"   => "openIdConnect",
  "key"    => "apiKey",
  "bearer" => "http",
  "linked" => nil,
} of String => String?

private def read(security : String, schemes : Hash(String, String?)? = SCHEMES) : Array(Array(String))
  requirements = YAML.parse(security).as_a.map { |node| OasSecurityAccess.requirement(node) }
  OasSecurityAccess.cnf(requirements, schemes).map(&.map(&.to_s).sort!).sort!
end

describe OasSecurityAccess do
  {
    "[{oauth: [read, write]}]"            => [["scope:read"], ["scope:write"]],
    "[{oidc: [profile]}]"                 => [["scope:profile"]],
    "[{oauth: []}]"                       => [["authenticated"]],
    "[{key: []}]"                         => [["authenticated"]],
    "[{oauth: [read], key: []}]"          => [["authenticated"], ["scope:read"]],
    "[{oauth: [read]}, {key: []}]"        => [["authenticated", "scope:read"]],
    "[{oauth: [a, b]}, {oidc: [c]}]"      => [["scope:a", "scope:c"], ["scope:b", "scope:c"]],
    "[{oauth: [read]}, {bearer: []}, {}]" => [] of Array(String),
    "[{nosuch: []}]"                      => [["unresolved"]],
    "[{key: []}, {nosuch: []}]"           => [["authenticated", "unresolved"]],
    "[{key: [admin]}]"                    => [["authenticated"], ["unresolved"]],
    "[{linked: [read]}]"                  => [["authenticated"], ["unresolved"]],
    "[{linked: []}]"                      => [["authenticated"]],
    "[{oauth: read}]"                     => [["authenticated"], ["unresolved"]],
    "[{oauth: [read, {x: 1}]}]"           => [["authenticated"], ["unresolved"]],
    "[bearer, {key: []}]"                 => [["authenticated", "unresolved"]],
    "[{oauth: !!binary aGk=}]"            => [["authenticated"], ["unresolved"]],
  }.each do |security, expected|
    it "reads #{security}" do
      read(security).should eq(expected)
    end
  end

  it "keeps the text it could not read" do
    requirements = YAML.parse("[{key: [admin, ops]}, {nosuch: []}, {oauth: read}, bearer]").as_a.map { |node| OasSecurityAccess.requirement(node) }
    requirements.map { |requirement| OasSecurityAccess.cnf([requirement], SCHEMES).flatten.select(&.kind.unresolved?).map(&.value) }
      .should eq([["key: admin, ops"], ["nosuch"], ["oauth: \"read\""], ["\"bearer\""]])
  end

  it "reads every scheme as undefined when the document defines none" do
    read("[{oauth: [read]}, {key: []}]", nil).should eq([["unresolved", "unresolved"]])
  end

  it "reads JSON and YAML documents into equal requirements" do
    yaml = YAML.parse("[{oauth: [read]}, {key: [admin]}, plain]").as_a.map { |node| OasSecurityAccess.requirement(node) }
    json = JSON.parse(%([{"oauth": ["read"]}, {"key": ["admin"]}, "plain"])).as_a.map { |node| OasSecurityAccess.requirement(node) }
    json.should eq(yaml)
  end
end
