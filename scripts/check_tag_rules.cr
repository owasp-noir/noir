# Checks every built-in tag rule (src/tagger/rules/*.yml) against its own
# examples without building noir or the spec suite.
#
# It makes the same assertions as the "built-in tag rules" block of
# spec/unit_test/tagger/rule_tagger_spec.cr, but needs only the rule loader,
# so it answers in seconds instead of after a full compile. CI runs it for any
# change under src/tagger/rules, which is what lets a pull request that only
# edits a rule skip the heavier jobs.
#
#   crystal run scripts/check_tag_rules.cr
#
# Exits 1 if any rule fails to load or gets one of its examples wrong.
require "../src/tagger/rule_tagger"

RULES_DIR = "src/tagger/rules"

failures = 0

NoirTagRules::BUILTIN_SOURCES.each do |file, content|
  path = "#{RULES_DIR}/#{file}"
  problems = [] of String

  begin
    rule = NoirTagRules.parse(content, file)
    problems << "no examples under 'match'" if rule.match_examples.empty?
    problems << "no examples under 'no_match'" if rule.no_match_examples.empty?
    stem = File.basename(file, File.extname(file))
    problems << "file must be named #{rule.key}#{File.extname(file)}, after the rule's key" unless stem == rule.key
    problems.concat NoirTagRules.example_failures(rule)
    puts "ok    #{path} (#{rule.match_examples.size + rule.no_match_examples.size} examples)" if problems.empty?
  rescue ex : NoirTagRules::RuleError | YAML::ParseException
    # The loader prefixes its messages with the file name; drop it, the path
    # is printed below.
    problems << (ex.message || ex.class.name).lchop("#{file}: ")
  end

  problems.each do |problem|
    failures += 1
    puts "FAIL  #{path}: #{problem}"
    # Shows up next to the file in the pull request's "Files changed" tab.
    puts "::error file=#{path}::#{problem}" if ENV["GITHUB_ACTIONS"]? == "true"
  end
end

if failures > 0
  puts
  puts "#{failures} problem(s). The rule format is described in #{RULES_DIR}/README.md."
  exit 1
end
