require "../../spec_helper"
require "../../../src/tagger/tagger.cr"

private def rule_options
  {
    "debug"   => YAML::Any.new(false),
    "verbose" => YAML::Any.new(false),
    "color"   => YAML::Any.new(false),
    "nolog"   => YAML::Any.new(false),
  }
end

private def rule_yaml(match : String) : String
  <<-YAML
    key: sample
    name: Sample Tagger
    summary: sample
    order: 999
    tag: { tagger: Sample, description: sample }
    match: #{match}
    YAML
end

private def tagged?(rule : NoirTagRules::Rule, endpoint : Endpoint) : Bool
  copy = Endpoint.new(endpoint.url, endpoint.method, endpoint.params.dup)
  copy.protocol = endpoint.protocol
  RuleTagger.new(rule_options, rule).perform([copy])
  copy.tags.any? { |tag| tag.name == rule.tag_name }
end

private def describe_example(endpoint : Endpoint) : String
  params = endpoint.params.map { |p| "#{p.param_type}:#{p.name}=#{p.value}" }.join(", ")
  "#{endpoint.method} #{endpoint.url} (#{endpoint.protocol}) [#{params}]"
end

# Every built-in rule is its own test: the examples in the YAML are the
# spec, so a contributor adding a rule writes no Crystal.
describe "built-in tag rules (src/tagger/rules)" do
  it "ships at least one rule" do
    NoirTagRules::BUILTIN.should_not be_empty
  end

  NoirTagRules::BUILTIN.each do |rule|
    describe rule.source do
      it "has match and no_match examples" do
        rule.match_examples.should_not be_empty
        rule.no_match_examples.should_not be_empty
      end

      it "names its file after its key" do
        File.basename(rule.source, File.extname(rule.source)).should eq(rule.key)
      end

      it "tags every match example" do
        missed = rule.match_examples.reject { |ep| tagged?(rule, ep) }
        fail "not tagged: #{missed.map { |ep| describe_example(ep) }}" unless missed.empty?
      end

      it "tags no no_match example" do
        hit = rule.no_match_examples.select { |ep| tagged?(rule, ep) }
        fail "tagged: #{hit.map { |ep| describe_example(ep) }}" unless hit.empty?
      end

      it "is built through the registry under its key" do
        NoirTaggers.build(rule.key, rule_options).try(&.name).should eq(rule.key)
      end
    end
  end
end

describe NoirTagRules do
  it "matches param names regardless of case and separators" do
    rule = NoirTagRules.parse(rule_yaml("{ param: { name: is_admin } }"), "t.yml")
    tagged?(rule, Endpoint.new("/x", "POST", [Param.new("isAdmin", "", "json")])).should be_true
    tagged?(rule, Endpoint.new("/x", "POST", [Param.new("is-admin", "", "json")])).should be_true
  end

  it "treats a mapping with several keys as all of them" do
    rule = NoirTagRules.parse(rule_yaml("{ method: POST, path_segment: upload }"), "t.yml")
    tagged?(rule, Endpoint.new("/upload", "POST")).should be_true
    tagged?(rule, Endpoint.new("/upload", "GET")).should be_false
  end

  it "expands `safe` in method lists" do
    rule = NoirTagRules.parse(rule_yaml("{ method_not: safe }"), "t.yml")
    tagged?(rule, Endpoint.new("/x", "QUERY")).should be_false
    tagged?(rule, Endpoint.new("/x", "DELETE")).should be_true
  end

  it "counts matching params against min" do
    rule = NoirTagRules.parse(rule_yaml("{ param: { type: header, name: [a, b], min: 2 } }"), "t.yml")
    tagged?(rule, Endpoint.new("/x", "GET", [Param.new("a", "", "header")])).should be_false
    tagged?(rule, Endpoint.new("/x", "GET", [Param.new("a", "", "header"), Param.new("b", "", "header")])).should be_true
    tagged?(rule, Endpoint.new("/x", "GET", [Param.new("a", "", "header"), Param.new("b", "", "query")])).should be_false
  end

  it "defaults the tag name to the key and copies the tag text" do
    rule = NoirTagRules.parse(rule_yaml("{ path_segment: x }"), "t.yml")
    endpoint = Endpoint.new("/x", "GET")
    RuleTagger.new(rule_options, rule).perform([endpoint])
    endpoint.tags.map { |t| {t.name, t.tagger, t.description} }.should eq([{"sample", "Sample", "sample"}])
  end

  describe "rejects at load time" do
    {
      "an unknown condition"              => rule_yaml("{ path_segmnt: admin }"),
      "an unknown param filter"           => rule_yaml("{ param: { nme: x } }"),
      "a param with no filter"            => rule_yaml("{ param: { min: 2 } }"),
      "a segment that can never match"    => rule_yaml("{ path_segment: wp-admin }"),
      "an empty any"                      => rule_yaml("{ any: [] }"),
      "an unknown top-level key"          => rule_yaml("{ path_segment: x }") + "\nseverity: high",
      "a missing tag description"         => rule_yaml("{ path_segment: x }").sub("description: sample", "description: ''"),
      "a key outside [a-z0-9_]"           => rule_yaml("{ path_segment: x }").sub("key: sample", "key: Sample-Tag"),
      "a non-integer min"                 => rule_yaml("{ param: { name: x, min: two } }"),
      "an example with an unknown field"  => rule_yaml("{ path_segment: x }") + "\nexamples: { match: [{ uri: /x }] }",
      "a non-mapping condition in a list" => rule_yaml("{ any: [admin] }"),
    }.each do |what, yaml|
      it what do
        expect_raises(NoirTagRules::RuleError, /t\.yml/) { NoirTagRules.parse(yaml, "t.yml") }
      end
    end
  end
end
