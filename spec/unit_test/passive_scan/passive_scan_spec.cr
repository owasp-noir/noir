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

  # Regression tests for the matchers-condition: or early-out. Prior to
  # the perf fix, this branch iterated every line of every file for each
  # matcher regardless of whether the matcher could possibly fire — the
  # early-out skips the line scan when no matcher matches the whole
  # file, so both of these cases must still behave identically.
  describe "matchers-condition: or" do
    it "returns results when at least one matcher fires" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: or-branch-hit
          info:
            name: or branch hit
            author: [test]
            severity: critical
            description: ...
            reference: [https://example.com]
          matchers-condition: or
          matchers:
            - type: word
              patterns:
                - needle-one
              condition: or
            - type: word
              patterns:
                - needle-two
              condition: or
          category: security
          techs: ['*']
          YAML
      ]
      file_content = "line one has nothing\nline two has needle-one here\nline three has needle-two too"
      results = NoirPassiveScan.detect("test.txt", file_content, rules, logger)

      results.size.should eq(2)
      results.map(&.line_number).should eq([2, 3])
    end

    it "still returns results for the matching matcher when another in the same rule doesn't fire" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: or-branch-mixed
          info:
            name: or branch mixed
            author: [test]
            severity: critical
            description: ...
            reference: [https://example.com]
          matchers-condition: or
          matchers:
            - type: word
              patterns:
                - present-needle
              condition: or
            - type: word
              patterns:
                - absent-needle
              condition: or
          category: security
          techs: ['*']
          YAML
      ]
      file_content = "first line\nsecond line has present-needle\nthird line"
      results = NoirPassiveScan.detect("test.txt", file_content, rules, logger)

      results.size.should eq(1)
      results[0].line_number.should eq(2)
    end

    it "emits one result per matching line regardless of how many matchers fire on it" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: or-branch-multi
          info:
            name: or branch multi
            author: [test]
            severity: critical
            description: ...
            reference: [https://example.com]
          matchers-condition: or
          matchers:
            - type: word
              patterns:
                - alpha
              condition: or
            - type: word
              patterns:
                - beta
              condition: or
          category: security
          techs: ['*']
          YAML
      ]
      # Line 1: matches alpha only. Line 2: matches both. Line 3: matches beta only.
      file_content = "alpha line\nalpha and beta both here\nbeta line"
      results = NoirPassiveScan.detect("test.txt", file_content, rules, logger)

      # One finding per matching line — line 2 is a single result
      # even though both `alpha` and `beta` matchers fire on it,
      # because the rule already triggered for the same (rule × line)
      # finding (the matchers are joined by `or`, so any hit is the
      # whole-rule hit). Pre-fix this was 4 (duplicating line 2).
      results.size.should eq(3)
      results.map(&.line_number).should eq([1, 2, 3])
    end

    it "returns no results and takes the early-out when no matcher fires" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: or-branch-miss
          info:
            name: or branch miss
            author: [test]
            severity: critical
            description: ...
            reference: [https://example.com]
          matchers-condition: or
          matchers:
            - type: word
              patterns:
                - absent-one
              condition: or
            - type: word
              patterns:
                - absent-two
              condition: or
          category: security
          techs: ['*']
          YAML
      ]
      file_content = "nothing to match here\non any line at all\nreally, nothing"
      results = NoirPassiveScan.detect("test.txt", file_content, rules, logger)

      results.size.should eq(0)
    end

    # Pre-fix this loop pushed one PassiveScanResult per matcher hit
    # per line. Most secret-detection rules (aws-access-key,
    # github-token, …) ship with both a `word` and a `regex` matcher
    # joined by `or` so the bait line "AWS_ACCESS_KEY_ID = AKIA…"
    # satisfied both — emitting the same finding twice per line.
    # Verifies one entry per (rule × line), regardless of how many
    # matchers fire on that line.
    it "emits one result per matching line even when multiple OR matchers fire" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-'YAML')),
          id: or-double-fire
          info:
            name: double fire
            author: [test]
            severity: critical
            description: ...
            reference: []
          matchers-condition: or
          matchers:
            - type: word
              patterns:
                - SECRET
              condition: or
            - type: regex
              patterns:
                - SECRET\\s*=\\s*['"]?[A-Z0-9]+['"]?
              condition: or
          category: secret
          techs: ['*']
          YAML
      ]
      file_content = %(SECRET = "ABC123"\nunrelated line\nSECRET = "DEF456")
      results = NoirPassiveScan.detect("test.txt", file_content, rules, logger)

      # Pre-fix the bait lines (1 and 3) each emitted 2 results
      # (word + regex). Post-fix exactly one per matching line.
      results.size.should eq(2)
      results.map(&.line_number).sort!.should eq([1, 3])
    end
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

  # End-to-end suppression of secret-rule false positives. The bundled
  # secret rules pair a `word` matcher on a variable *name*
  # (GITHUB_TOKEN, AWS_ACCESS_KEY_ID, …) with a `regex` matcher on the
  # value shape, joined by `or`. The word matcher fires on any line that
  # merely *references* the variable — CI templating (`${{ … }}`), env
  # reads (`os.getenv`), placeholders — which are not leaked secrets.
  describe "secret false-positive suppression" do
    github_token_rule = <<-YAML
      id: github-token
      info:
        name: Detect GITHUB_TOKEN
        author: [test]
        severity: critical
        description: ...
        reference: []
      matchers-condition: or
      matchers:
        - type: word
          patterns: [GITHUB_TOKEN, GH_TOKEN]
          condition: or
        - type: regex
          patterns: ['ghp_[A-Za-z0-9]{36}']
          condition: or
      category: secret
      techs: ['*']
      YAML

    it "suppresses a GitHub Actions templating reference" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [PassiveScan.new(YAML.parse(github_token_rule))]
      content = "jobs:\n  build:\n    env:\n      GH_TOKEN: ${{ github.token }}"
      results = NoirPassiveScan.detect("ci.yml", content, rules, logger)
      results.size.should eq(0)
    end

    it "suppresses an env-var accessor reference" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [PassiveScan.new(YAML.parse(github_token_rule))]
      content = %(const token = process.env.GITHUB_TOKEN)
      results = NoirPassiveScan.detect("app.js", content, rules, logger)
      results.size.should eq(0)
    end

    it "still reports a hard-coded literal token" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [PassiveScan.new(YAML.parse(github_token_rule))]
      content = "GITHUB_TOKEN=ghp_1234567890abcdefghijklmnopqrstuvwx"
      results = NoirPassiveScan.detect(".env", content, rules, logger)
      results.size.should eq(1)
      results[0].line_number.should eq(1)
    end

    it "does not suppress non-secret categories sharing the same shape" do
      logger = NoirLogger.new(false, false, false, true)
      rule = <<-YAML
        id: ci-ref
        info:
          name: CI token reference
          author: [test]
          severity: high
          description: ...
          reference: []
        matchers-condition: or
        matchers:
          - type: word
            patterns: [GITHUB_TOKEN]
            condition: or
        category: security
        techs: ['*']
        YAML
      rules = [PassiveScan.new(YAML.parse(rule))]
      content = "GH ref: ${{ secrets.GITHUB_TOKEN }}"
      results = NoirPassiveScan.detect("ci.yml", content, rules, logger)
      results.size.should eq(1)
    end
  end

  describe "edge cases" do
    it "returns no results when the rule has empty patterns" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: empty-patterns
          info:
            name: empty patterns rule
            author: [test]
            severity: critical
            description: ...
            reference: []
          matchers-condition: or
          matchers:
            - type: word
              patterns: []
              condition: or
          category: security
          techs: ['*']
          YAML
      ]
      # Previously the `matcher.patterns && matcher.patterns.all?` shape
      # treated an empty array as "every match passes" → every file
      # silently flagged. The empty-patterns short circuit must drop
      # this rule entirely.
      results = NoirPassiveScan.detect("test.txt", "any content at all", rules, logger)
      results.size.should eq(0)
    end

    it "returns no results when regex compilation failed (no retry per line)" do
      logger = NoirLogger.new(false, false, false, true)
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: bad-regex
          info:
            name: bad regex
            author: [test]
            severity: critical
            description: ...
            reference: []
          matchers-condition: or
          matchers:
            - type: regex
              patterns:
                - "[unterminated"
              condition: or
          category: security
          techs: ['*']
          YAML
      ]
      # The matcher must mark itself as compilation-failed so the
      # per-line loop short-circuits without retrying Regex.new.
      rules[0].matchers[0].regex_compile_failed?.should be_true
      results = NoirPassiveScan.detect("test.txt", "any\ncontent", rules, logger)
      results.size.should eq(0)
    end

    it "precomputes string_patterns at Matcher construction" do
      matcher = PassiveScan::Matcher.new(YAML.parse(<<-YAML))
        type: word
        patterns:
          - alpha
          - beta
        condition: or
        YAML
      matcher.string_patterns.should eq(["alpha", "beta"])
    end
  end

  describe "filter_rules_by_severity" do
    it "drops rules below the threshold once for the whole scan" do
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: keep
          info: { name: keep, author: [t], severity: critical, description: ., reference: [] }
          matchers-condition: or
          matchers:
            - { type: word, patterns: [k], condition: or }
          category: security
          techs: ['*']
          YAML
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: drop
          info: { name: drop, author: [t], severity: low, description: ., reference: [] }
          matchers-condition: or
          matchers:
            - { type: word, patterns: [d], condition: or }
          category: security
          techs: ['*']
          YAML
      ]
      filtered = NoirPassiveScan.filter_rules_by_severity(rules, "high")
      filtered.map(&.id).should eq(["keep"])
    end

    it "returns an empty list when nothing meets the threshold" do
      rules = [
        PassiveScan.new(YAML.parse(<<-YAML)),
          id: only-low
          info: { name: low, author: [t], severity: low, description: ., reference: [] }
          matchers-condition: or
          matchers:
            - { type: word, patterns: [x], condition: or }
          category: security
          techs: ['*']
          YAML
      ]
      NoirPassiveScan.filter_rules_by_severity(rules, "critical").should be_empty
    end
  end

  describe "PassiveScan#valid?" do
    it "rejects rules with an empty info.name" do
      yaml = YAML.parse <<-YAML
        id: missing-name
        info:
          name: ""
          author: [test]
          severity: critical
          description: ...
          reference: []
        matchers-condition: or
        matchers:
          - type: word
            patterns: [needle]
            condition: or
        category: security
        techs: ['*']
        YAML
      PassiveScan.new(yaml).valid?.should be_false
    end

    it "rejects rules with no matchers" do
      yaml = YAML.parse <<-YAML
        id: no-matchers
        info:
          name: empty
          author: [test]
          severity: critical
          description: ...
          reference: []
        matchers-condition: or
        matchers: []
        category: security
        techs: ['*']
        YAML
      PassiveScan.new(yaml).valid?.should be_false
    end

    it "accepts a well-formed rule" do
      yaml = YAML.parse <<-YAML
        id: well-formed
        info:
          name: ok
          author: [test]
          severity: critical
          description: ...
          reference: []
        matchers-condition: or
        matchers:
          - type: word
            patterns: [needle]
            condition: or
        category: security
        techs: ['*']
        YAML
      PassiveScan.new(yaml).valid?.should be_true
    end
  end
end
