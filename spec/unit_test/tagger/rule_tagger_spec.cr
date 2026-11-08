require "../../spec_helper"
require "../../../src/tagger/tagger.cr"
require "../../../src/cli_validation"
require "file_utils"

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

private def with_rule_dir(files : Hash(String, String), &)
  dir = File.join(Dir.tempdir, "noir-tag-rules-#{Random.new.hex(6)}")
  Dir.mkdir_p(dir)
  files.each do |name, content|
    path = File.join(dir, name)
    Dir.mkdir_p(File.dirname(path))
    File.write(path, content)
  end
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

private def custom_rule(key : String, order : Int32 = 999, extra : String = "") : String
  rule_yaml("{ path_segment: internal }").sub("key: sample", "key: #{key}").sub("order: 999", "order: #{order}") + extra
end

private def options_with_rules(paths : Array(String))
  rule_options.merge({"tagger_rules_path" => YAML::Any.new(paths.map { |p| YAML::Any.new(p) })})
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

      it "gets every example right" do
        failures = NoirTagRules.example_failures(rule)
        fail failures.join("\n") unless failures.empty?
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

  it "negates with not" do
    rule = NoirTagRules.parse(rule_yaml("{ path_segment: callback, not: { path_segment: oauth } }"), "t.yml")
    tagged?(rule, Endpoint.new("/pay/callback", "POST")).should be_true
    tagged?(rule, Endpoint.new("/oauth/callback", "POST")).should be_false
  end

  it "counts true conditions with at_least" do
    rule = NoirTagRules.parse(rule_yaml("{ at_least: { count: 2, of: [{ path_segment: a }, { path_segment: b }, { param: { name: c } }] } }"), "t.yml")
    tagged?(rule, Endpoint.new("/a", "GET")).should be_false
    tagged?(rule, Endpoint.new("/a/b", "GET")).should be_true
    tagged?(rule, Endpoint.new("/b", "GET", [Param.new("c", "", "query")])).should be_true
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
      "an at_least count above its list"  => rule_yaml("{ at_least: { count: 3, of: [{ path_segment: a }, { path_segment: b }] } }"),
      "an at_least with no count"         => rule_yaml("{ at_least: { of: [{ path_segment: a }] } }"),
    }.each do |what, yaml|
      it what do
        expect_raises(NoirTagRules::RuleError, /t\.yml/) { NoirTagRules.parse(yaml, "t.yml") }
      end
    end
  end
end

describe "--tagger-rules" do
  it "loads a directory recursively and a single file" do
    with_rule_dir({"a.yml" => custom_rule("team_a"), "nested/b.yaml" => custom_rule("team_b"), "notes.txt" => "x"}) do |dir|
      NoirTaggers.user_rules(options_with_rules([dir])).map(&.key).should eq(%w[team_a team_b])
      NoirTaggers.user_rules(options_with_rules([File.join(dir, "a.yml")])).map(&.key).should eq(%w[team_a])
    end
  end

  it "is empty when no path is configured" do
    NoirTaggers.user_rules(rule_options).should be_empty
  end

  {
    "a missing path"           => ->(dir : String) { [File.join(dir, "nope")] },
    "a directory with no rule" => ->(dir : String) { [File.join(dir, "empty")] },
  }.each do |what, paths|
    it "rejects #{what}" do
      with_rule_dir({"empty/README" => "x"}) do |dir|
        expect_raises(NoirTagRules::RuleError, /--tagger-rules/) { NoirTaggers.user_rules(options_with_rules(paths.call(dir))) }
      end
    end
  end

  it "rejects a key a built-in tagger already has" do
    with_rule_dir({"admin.yml" => custom_rule("admin")}) do |dir|
      expect_raises(NoirTagRules::RuleError, /admin\.yml: key 'admin' is already used/) { NoirTaggers.user_rules(options_with_rules([dir])) }
    end
  end

  it "rejects two user rules with one key" do
    with_rule_dir({"a.yml" => custom_rule("dup"), "b.yml" => custom_rule("dup")}) do |dir|
      expect_raises(NoirTagRules::RuleError, /b\.yml: key 'dup'/) { NoirTaggers.user_rules(options_with_rules([dir])) }
    end
  end

  it "names the file on a YAML syntax error" do
    with_rule_dir({"bad.yml" => "key: [unclosed"}) do |dir|
      expect_raises(NoirTagRules::RuleError, /bad\.yml/) { NoirTaggers.user_rules(options_with_rules([dir])) }
    end
  end

  it "surfaces a broken rule as a CLI validation error" do
    with_rule_dir({"bad.yml" => custom_rule("bad").sub("path_segment", "path_segmnt")}) do |dir|
      expect_raises(Noir::CliValidation::Error, /unknown condition 'path_segmnt'/) do
        Noir::CliValidation.validate_tagger_names!(options_with_rules([dir]))
      end
    end
  end

  it "lets --use-taggers name a custom key" do
    with_rule_dir({"a.yml" => custom_rule("team_a")}) do |dir|
      options = options_with_rules([dir]).merge({"use_taggers" => YAML::Any.new("team_a,hunt")})
      Noir::CliValidation.validate_tagger_names!(options)
    end
  end

  it "runs custom rules without any tagger selected, in order among the selected ones" do
    # order 115 sits between admin (110) and payment (120).
    with_rule_dir({"a.yml" => custom_rule("team_a", 115)}) do |dir|
      endpoint = Endpoint.new("/admin/internal/payments", "GET")
      NoirTaggers.run_tagger([endpoint], options_with_rules([dir]), "")
      endpoint.tags.map(&.name).should eq(%w[team_a])

      endpoint = Endpoint.new("/admin/internal/payments", "GET")
      NoirTaggers.run_tagger([endpoint], options_with_rules([dir]), "payment,admin")
      endpoint.tags.map(&.name).should eq(%w[admin team_a payment])
    end
  end

  it "reports a custom rule's wrong examples" do
    yaml = custom_rule("team_a", extra: "\nexamples: { match: [{ url: /public }], no_match: [{ url: /internal }] }")
    rule = NoirTagRules.parse(yaml, "team_a.yml")
    NoirTagRules.example_failures(rule).should eq([
      "not tagged: GET /public (http)",
      "tagged but listed under no_match: GET /internal (http)",
    ])
  end
end
