require "../../spec_helper"
require "../../../src/passive_scan/detect.cr"
require "../../../src/models/logger.cr"
require "../../../src/models/passive_scan.cr"

describe NoirPassiveScan do
  it "detects matches with 'and' condition" do
    logger = NoirLogger.new(false, false, false, true)
    rules = [
      PassiveScan.new(YAML.parse(<<-YAML)),
        id: hahwul-test
        info:
          name: use x-api-key
          author:
            - abcd
            - aaaa
          severity: critical
          description: ....
          reference:
            - https://google.com
        matchers-condition: and
        matchers:
          - type: word
            patterns:
              - test
              - content
            condition: and
        category: secret
        techs:
          - '*'
          - ruby-rails
        YAML
    ]
    file_content = "This is a test content.\nAnother test line."
    results = NoirPassiveScan.detect("test_file.txt", file_content, rules, logger)

    results.size.should eq(1)
    results[0].line_number.should eq(1)
  end

  it "detects matches with 'or' condition" do
    logger = NoirLogger.new(false, false, false, true)
    rules = [
      PassiveScan.new(YAML.parse(<<-YAML)),
        id: hahwul-test
        info:
          name: use x-api-key
          author:
            - abcd
            - aaaa
          severity: critical
          description: ....
          reference:
            - https://google.com
        matchers-condition: and
        matchers:
          - type: word
            patterns:
              - test
              - content
            condition: or
        category: secret
        techs:
          - '*'
          - ruby-rails
        YAML
    ]
    file_content = "This is a test content.\nAnother test line."
    results = NoirPassiveScan.detect("test_file.txt", file_content, rules, logger)

    results.size.should eq(2)
    results[0].line_number.should eq(1)
    results[1].line_number.should eq(2)
  end

  it "detects regex matches" do
    logger = NoirLogger.new(false, false, false, true)
    rules = [
      PassiveScan.new(YAML.parse(<<-YAML)),
        id: hahwul-test
        info:
          name: use x-api-key
          author:
            - abcd
            - aaaa
          severity: critical
          description: ....
          reference:
            - https://google.com
        matchers-condition: and
        matchers:
          - type: regex
            patterns:
              - ^This
            condition: or
        category: secret
        techs:
          - '*'
          - ruby-rails
        YAML
    ]
    file_content = "This is a test content.\nAnother test line."
    results = NoirPassiveScan.detect("test_file.txt", file_content, rules, logger)

    results.size.should eq(1)
    results[0].line_number.should eq(1)
  end

  describe "severity filtering" do
    it "filters by critical severity only" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-critical
          info:
            name: Critical Issue
            author:
              - test
            severity: critical
            description: Critical severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - critical
              condition: or
          category: security
          techs:
            - '*'
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-high
          info:
            name: High Issue
            author:
              - test
            severity: high
            description: High severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - high
              condition: or
          category: security
          techs:
            - '*'
          YAML
      ]
      file_content = "This is a critical issue and a high priority item."

      # Test critical only
      results = NoirPassiveScan.detect_with_severity("test_file.txt", file_content, rules, logger, "critical")
      results.size.should eq(1)
      results[0].info.severity.should eq("critical")
    end

    it "filters by high severity and above" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-critical
          info:
            name: Critical Issue
            author:
              - test
            severity: critical
            description: Critical severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - critical
              condition: or
          category: security
          techs:
            - '*'
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-high
          info:
            name: High Issue
            author:
              - test
            severity: high
            description: High severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - high
              condition: or
          category: security
          techs:
            - '*'
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-medium
          info:
            name: Medium Issue
            author:
              - test
            severity: medium
            description: Medium severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - medium
              condition: or
          category: security
          techs:
            - '*'
          YAML
      ]
      file_content = "This is a critical issue, a high priority item, and a medium concern."

      # Test high and above (should include critical and high, exclude medium)
      results = NoirPassiveScan.detect_with_severity("test_file.txt", file_content, rules, logger, "high")
      results.size.should eq(2)
      severities = results.map(&.info.severity)
      severities.should contain("critical")
      severities.should contain("high")
      severities.should_not contain("medium")
    end

    it "filters by medium severity and above" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-critical
          info:
            name: Critical Issue
            author:
              - test
            severity: critical
            description: Critical severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - critical
              condition: or
          category: security
          techs:
            - '*'
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-medium
          info:
            name: Medium Issue
            author:
              - test
            severity: medium
            description: Medium severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - medium
              condition: or
          category: security
          techs:
            - '*'
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-low
          info:
            name: Low Issue
            author:
              - test
            severity: low
            description: Low severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - low
              condition: or
          category: info
          techs:
            - '*'
          YAML
      ]
      file_content = "This is a critical issue, a medium concern, and a low priority item."

      # Test medium and above (should include critical and medium, exclude low)
      results = NoirPassiveScan.detect_with_severity("test_file.txt", file_content, rules, logger, "medium")
      results.size.should eq(2)
      severities = results.map(&.info.severity)
      severities.should contain("critical")
      severities.should contain("medium")
      severities.should_not contain("low")
    end

    it "includes all severities with low threshold" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-critical
          info:
            name: Critical Issue
            author:
              - test
            severity: critical
            description: Critical severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - critical
              condition: or
          category: security
          techs:
            - '*'
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: test-low
          info:
            name: Low Issue
            author:
              - test
            severity: low
            description: Low severity test
            reference:
              - https://example.com
          matchers-condition: and
          matchers:
            - type: word
              patterns:
                - low
              condition: or
          category: info
          techs:
            - '*'
          YAML
      ]
      file_content = "This is a critical issue and a low priority item."

      # Test low and above (should include all)
      results = NoirPassiveScan.detect_with_severity("test_file.txt", file_content, rules, logger, "low")
      results.size.should eq(2)
      severities = results.map(&.info.severity)
      severities.should contain("critical")
      severities.should contain("low")
    end
  end
end
