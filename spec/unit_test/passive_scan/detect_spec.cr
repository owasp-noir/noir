require "../../spec_helper"
require "../../../src/passive_scan/detect"

describe NoirPassiveScan do
  logger = NoirLogger.new(false, true, false, true)

  describe ".filter_rules_by_severity" do
    it "filters rules below the threshold severity" do
      high_rule_yaml = <<-YAML
        id: test-high
        category: sec
        techs: []
        info:
          name: High Rule
          author: []
          severity: high
          description: high severity
          reference: []
        matchers:
          - type: word
            condition: or
            patterns:
              - secret
        matchers-condition: or
        YAML

      low_rule_yaml = <<-YAML
        id: test-low
        category: sec
        techs: []
        info:
          name: Low Rule
          author: []
          severity: low
          description: low severity
          reference: []
        matchers:
          - type: word
            condition: or
            patterns:
              - debug
        matchers-condition: or
        YAML

      high_rule = PassiveScan.new(YAML.parse(high_rule_yaml))
      low_rule = PassiveScan.new(YAML.parse(low_rule_yaml))

      filtered = NoirPassiveScan.filter_rules_by_severity([high_rule, low_rule], "medium")
      filtered.size.should eq(1)
      filtered.first.info.name.should eq("High Rule")
    end

    it "treats a rule with no declared severity as invalid rather than filtering it silently" do
      no_sev_rule_yaml = <<-YAML
        id: test-no-sev
        category: sec
        techs: []
        info:
          name: No Severity Rule
          author: []
          description: no severity specified
          reference: []
        matchers:
          - type: word
            condition: or
            patterns:
              - secret
        matchers-condition: or
        YAML

      no_sev_rule = PassiveScan.new(YAML.parse(no_sev_rule_yaml))

      # `load_rules` drops it and warns, so it never reaches the severity
      # filter at all. That is the point: a rule silently filtered out reads
      # exactly like a rule that found nothing.
      no_sev_rule.info.severity.should eq("")
      no_sev_rule.valid?.should be_false
    end
  end

  describe ".detect" do
    it "detects pattern matches on lines" do
      rule_yaml = <<-YAML
        id: test-key
        category: sec
        techs: []
        info:
          name: API Key Detector
          author: []
          severity: high
          description: api key
          reference: []
        matchers:
          - type: word
            condition: or
            patterns:
              - AKIAIOSFODNN7EXAMPLE
        matchers-condition: or
        YAML
      rule = PassiveScan.new(YAML.parse(rule_yaml))
      content = "line 1\nkey = AKIAIOSFODNN7EXAMPLE\nline 3"

      results = NoirPassiveScan.detect("config.py", content, [rule], logger)
      results.size.should eq(1)
      results.first.line_number.should eq(2)
      results.first.extract.should contain("AKIAIOSFODNN7EXAMPLE")
    end

    it "supports AND condition for matchers" do
      rule_yaml = <<-YAML
        id: test-secret
        category: sec
        techs: []
        info:
          name: Secret Keyword
          author: []
          severity: high
          description: secret
          reference: []
        matchers:
          - type: word
            condition: or
            patterns:
              - AWS_KEY
          - type: word
            condition: or
            patterns:
              - secret_value
        matchers-condition: and
        YAML
      rule = PassiveScan.new(YAML.parse(rule_yaml))
      content = "AWS_KEY = secret_value"

      results = NoirPassiveScan.detect("config.py", content, [rule], logger)
      results.size.should eq(1)
    end

    it "detects matches with omitted matchers-condition on single matcher" do
      rule_yaml = <<-YAML
        id: test-single
        category: sec
        techs: []
        info:
          name: Single Matcher Rule
          author: []
          severity: high
          description: single matcher
          reference: []
        matchers:
          - type: word
            condition: or
            patterns:
              - MY_SECRET_TOKEN
        YAML
      rule = PassiveScan.new(YAML.parse(rule_yaml))
      content = "MY_SECRET_TOKEN = 'abc123xyz'"

      results = NoirPassiveScan.detect("config.py", content, [rule], logger)
      results.size.should eq(1)
      results.first.extract.should contain("MY_SECRET_TOKEN")
    end

    it "detects matches with uppercase condition: OR and type: WORD / REGEX" do
      word_rule_yaml = <<-YAML
        id: test-upper-word
        category: sec
        techs: []
        info:
          name: Upper Word Rule
          author: []
          severity: high
          description: uppercase condition
          reference: []
        matchers-condition: OR
        matchers:
          - type: WORD
            condition: OR
            patterns:
              - TARGET_STRING
        YAML
      regex_rule_yaml = <<-YAML
        id: test-upper-regex
        category: sec
        techs: []
        info:
          name: Upper Regex Rule
          author: []
          severity: high
          description: uppercase regex
          reference: []
        matchers-condition: OR
        matchers:
          - type: REGEX
            condition: OR
            patterns:
              - "TOKEN_[A-Z0-9]{8}"
        YAML
      word_rule = PassiveScan.new(YAML.parse(word_rule_yaml))
      regex_rule = PassiveScan.new(YAML.parse(regex_rule_yaml))
      content = "TARGET_STRING\nTOKEN_ABCD1234"

      results = NoirPassiveScan.detect("test.txt", content, [word_rule, regex_rule], logger)
      results.size.should eq(2)
      results.map(&.id).should eq(["test-upper-word", "test-upper-regex"])
    end

    it "matches word patterns literally, under both conditions" do
      rule_for = ->(condition : String) do
        PassiveScan.new(YAML.parse(
          "id: literal-#{condition}\ncategory: sec\ntechs: []\n" \
          "info: {name: literal, author: [], severity: high, description: literal, reference: []}\n" \
          "matchers-condition: or\nmatchers:\n  - {type: word, condition: #{condition}, patterns: ['a.b', 'x+y']}\n"))
      end
      or_rule = rule_for.call("or")
      and_rule = rule_for.call("and")

      NoirPassiveScan.detect("f", "axb\nxxy", [or_rule, and_rule], logger).should be_empty
      NoirPassiveScan.detect("f", "a.b", [or_rule], logger).map(&.line_number).should eq([1])
      NoirPassiveScan.detect("f", "a.b\nx+y", [and_rule], logger).should be_empty
      NoirPassiveScan.detect("f", "a.b x+y\nnone", [and_rule], logger).map(&.line_number).should eq([1])
    end
  end

  describe "a rule that raises" do
    rule_for = ->(id : String, pattern : String) do
      PassiveScan.new(YAML.parse(
        "id: #{id}\ncategory: sec\ntechs: []\n" \
        "info: {name: #{id}, author: [], severity: high, description: d, reference: []}\n" \
        "matchers-condition: or\nmatchers:\n  - {type: regex, condition: or, patterns: ['#{pattern}']}\n"))
    end

    before_each { Noir::SkippedFiles.clear }
    after_each { Noir::SkippedFiles.clear }

    it "costs only its own findings and is recorded as a gap" do
      # Catastrophic backtracking: PCRE2 raises "match limit exceeded" on
      # the run of `a`s that cannot end the line.
      slow = rule_for.call("slow-rule", %q((\w+\s?)+$))
      token = rule_for.call("token-rule", "tok_[a-z0-9]{12}")
      content = %(api = "tok_abcdef123456"\n#{"a" * 60}!\n)

      # The raising rule runs first, so a rescue around the whole file would
      # also lose the token rule that runs after it.
      results = NoirPassiveScan.detect("conf.txt", content, [slow, token], nil)
      results.map { |r| {r.id, r.line_number} }.should contain({"token-rule", 1})

      failures = Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Scan)
      failures.size.should eq(1)
      failures[0].tech.should eq(Noir::SkippedFiles::PASSIVE_SCAN_SCOPE)
      failures[0].message.should contain("conf.txt (rule slow-rule)")
      failures[0].message.should contain("match limit")
    end
  end

  describe "or-regex matchers" do
    rule_with = ->(patterns : Array(String)) do
      yaml = {
        "id"                 => "union-test",
        "category"           => "sec",
        "techs"              => [] of String,
        "info"               => {"name" => "u", "author" => [] of String, "severity" => "high", "description" => "d", "reference" => [] of String},
        "matchers-condition" => "or",
        "matchers"           => [{"type" => "regex", "condition" => "or", "patterns" => patterns}],
      }.to_yaml
      PassiveScan.new(YAML.parse(yaml))
    end

    it "keeps a backreference pointing at its own group" do
      # Folded into one union, `\1` would refer to the first pattern's group.
      rule = rule_with.call([%q((foo|bar)_key), %q((["'])tok_[a-z]{6}\1)])
      rule.valid?.should be_true
      NoirPassiveScan.detect("f", %(x = "tok_abcdef"\ny = "tok_abcdef'\n), [rule], nil).map(&.line_number).should eq([1])
    end

    it "loads and matches an extended-mode pattern with a comment" do
      rule = rule_with.call(["(?x) secret_[a-z]{4}  # trailing comment", "other_marker"])
      rule.valid?.should be_true
      NoirPassiveScan.detect("f", "a\nsecret_abcd\nother_marker\n", [rule], nil).map(&.line_number).should eq([2, 3])
    end

    it "matches patterns that reuse a group name" do
      rule = rule_with.call(["apikey=(?<v>[a-z0-9]{8})", "secret=(?<v>[a-z0-9]{8})"])
      rule.valid?.should be_true
      NoirPassiveScan.detect("f", "url?apikey=abcd1234\nsecret=abcd1234\n", [rule], nil).map(&.line_number).should eq([1, 2])
    end

    it "still folds plain patterns into one union" do
      matcher = rule_with.call(["foo_[0-9]+", "bar_[a-z]+"]).matchers.first
      matcher.compiled_regex.should_not be_nil
      matcher.regex_match?("x bar_abc").should be_true
      matcher.regex_match?("x baz").should be_false
    end

    it "agrees with the false-positive gate on what fired" do
      rule = rule_with.call([%q((foo|bar)_key), %q((["'])tok_[a-z]{6}\1)])
      NoirPassiveScan::FalsePositive.regex_value_hit?(rule, %(x = "tok_abcdef")).should be_true
    end
  end

  describe "anchored regex rules" do
    rule_with = ->(condition : String, patterns : Array(String)) do
      yaml = {
        "id"                 => "anchor-test",
        "category"           => "sec",
        "techs"              => [] of String,
        "info"               => {"name" => "a", "author" => [] of String, "severity" => "high", "description" => "d", "reference" => [] of String},
        "matchers-condition" => "or",
        "matchers"           => [{"type" => "regex", "condition" => condition, "patterns" => patterns}],
      }.to_yaml
      PassiveScan.new(YAML.parse(yaml))
    end

    it "fires `^` on a line other than the first" do
      rule = rule_with.call("or", [%q(^\s*db_password\s*=\s*\S+)])
      NoirPassiveScan.detect("f", "x = 1\n  db_password = hunter2\nlast\n", [rule], nil).map(&.line_number).should eq([2])
    end

    it "fires `$` on a middle line, including CRLF files" do
      rule = rule_with.call("or", [%q(db_password = \S+$)])
      NoirPassiveScan.detect("f", "a\ndb_password = abc\nlast\n", [rule], nil).map(&.line_number).should eq([2])
      NoirPassiveScan.detect("f", "a\r\ndb_password = abc\r\nlast\r\n", [rule], nil).map(&.line_number).should eq([2])
    end

    it "gates anchored patterns under condition: and" do
      rule = rule_with.call("and", [%q(^token:), %q([a-f0-9]{8}$)])
      NoirPassiveScan.detect("f", "x\ntoken: deadbeef\ny\n", [rule], nil).map(&.line_number).should eq([2])
    end

    it "keeps a gate for lookaround patterns, folded with plain ones" do
      matcher = rule_with.call("or", [%q((?<![A-Za-z0-9])AKZn[0-9A-Z]{16}(?![A-Za-z0-9])), "plain_[a-z]{4}"]).matchers.first
      # Pruned on a file with no candidate, kept on one with one.
      matcher.regex_may_match_file?("nothing to see\nhere\n").should be_false
      matcher.regex_may_match_file?("x\nplain_abcd\n").should be_true
      matcher.regex_may_match_file?("x\nk = AKZnABCDEFGHIJKLMNOP\n").should be_true
    end

    it "gates a mixed or-matcher on both its plain and anchored patterns" do
      matcher = rule_with.call("or", ["plain_[a-z]{4}", %q(^\s*key\s*=)]).matchers.first
      matcher.regex_may_match_file?("nothing\n").should be_false
      matcher.regex_may_match_file?("x\n  key = 1\n").should be_true
      matcher.regex_may_match_file?("x\nplain_abcd\n").should be_true
    end

    it "does not gate absolute anchors" do
      rule = rule_with.call("or", [%q(\Asecret_[a-z]+)])
      NoirPassiveScan.detect("f", "x\nsecret_abc\n", [rule], nil).map(&.line_number).should eq([2])
    end

    it "falls back to the per-line loop when the gate hits the match limit" do
      # Across the newlines the nested quantifier backtracks over every word
      # in the file; on each short line it gives up at once.
      rule = rule_with.call("or", [%q((\w+\s?)+!x)])
      content = ("aaaa\n" * 40) + "ab!x\n"
      Noir::SkippedFiles.clear
      NoirPassiveScan.detect("f", content, [rule], nil).map(&.line_number).should eq([41])
      Noir::SkippedFiles.failures.should be_empty
    end

    it "treats a negated class as no anchor" do
      PassiveScan::Matcher.line_anchored?(%q(mongodb://[^:/\s]+:[^@/\s]+@)).should be_false
      PassiveScan::Matcher.line_anchored?(%q(cost \$5 [$^]x)).should be_false
      PassiveScan::Matcher.line_anchored?(%q([]^]x$)).should be_true
    end
  end
end
