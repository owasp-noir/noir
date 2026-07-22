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
  end
end
