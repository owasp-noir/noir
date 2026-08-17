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
  end
end
