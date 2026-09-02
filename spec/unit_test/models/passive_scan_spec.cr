require "../../spec_helper"
require "../../../src/models/logger.cr"
require "../../../src/models/passive_scan.cr"
require "yaml"

describe "PassiveScan" do
  describe "Info" do
    it "initializes from YAML" do
      yaml_str = <<-YAML
        name: "Test Rule"
        author:
          - "Test Author"
        severity: "high"
        description: "Test description"
        reference:
          - "https://example.com"
        YAML
      yaml = YAML.parse(yaml_str)
      info = PassiveScan::Info.new(yaml)

      info.name.should eq("Test Rule")
      info.severity.should eq("high")
      info.description.should eq("Test description")
      info.author.size.should eq(1)
      info.reference.size.should eq(1)
    end
    it "handles missing optional fields with defaults" do
      yaml_str = <<-YAML
        name: "Minimal Info"
        YAML
      yaml = YAML.parse(yaml_str)
      info = PassiveScan::Info.new(yaml)

      info.name.should eq("Minimal Info")
      # Left empty rather than defaulted — see `PassiveScan#validation_errors`,
      # which rejects the rule by name. Any default below the `high` the
      # `--passive-scan-severity` option ships with would silently filter the
      # rule out instead.
      info.severity.should eq("")
      info.description.should eq("")
      info.author.should eq([] of YAML::Any)
      info.reference.should eq([] of YAML::Any)
    end
  end

  describe "Matcher" do
    it "initializes from YAML" do
      yaml_str = <<-YAML
        type: "regex"
        patterns:
          - "test.*pattern"
        condition: "or"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.type.should eq("regex")
      matcher.patterns.size.should eq(1)
      matcher.condition.should eq("or")
      matcher.valid?.should be_true
      matcher.regex_compile_failed?.should be_false
      matcher.compiled_regex.should_not be_nil
    end

    it "normalizes uppercase type and condition to lowercase" do
      yaml_str = <<-YAML
        type: "REGEX"
        patterns:
          - "test.*pattern"
        condition: "OR"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.type.should eq("regex")
      matcher.condition.should eq("or")
      matcher.valid?.should be_true
      matcher.compiled_regex.should_not be_nil
    end

    it "compiles individual regexes for condition: and" do
      yaml_str = <<-YAML
        type: "regex"
        patterns:
          - "pattern1"
          - "pattern2"
        condition: "AND"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.type.should eq("regex")
      matcher.condition.should eq("and")
      matcher.valid?.should be_true
      matcher.compiled_regexes.should_not be_nil
      matcher.compiled_regexes.try(&.size).should eq(2)
    end

    it "rejects invalid matcher type" do
      yaml_str = <<-YAML
        type: "keyword"
        patterns:
          - "test"
        condition: "or"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.valid?.should be_false
      matcher.validation_errors.should contain("invalid type \"keyword\" (expected 'word' or 'regex')")
    end

    it "rejects invalid matcher condition" do
      yaml_str = <<-YAML
        type: "word"
        patterns:
          - "test"
        condition: "xor"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.valid?.should be_false
      matcher.validation_errors.should contain("invalid condition \"xor\" (expected 'and' or 'or')")
    end

    it "rejects empty patterns list" do
      yaml_str = <<-YAML
        type: "word"
        patterns: []
        condition: "or"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.valid?.should be_false
      matcher.validation_errors.should contain("missing or empty 'patterns'")
    end

    it "rejects a blank pattern entry, which would match every line" do
      # `- ` with nothing after it is YAML null, which stringifies to "" —
      # and `line.includes?("")` is true for every line of every file.
      yaml_str = <<-YAML
        type: "word"
        patterns:
          - MARKER
          -
        condition: "or"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.valid?.should be_false
      matcher.validation_errors.should contain("empty pattern at index 1 (an empty pattern matches every line)")
    end

    it "rejects an explicitly empty regex pattern" do
      yaml_str = <<-YAML
        type: "regex"
        patterns: ['']
        condition: "or"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.valid?.should be_false
      matcher.validation_errors.should contain("empty pattern at index 0 (an empty pattern matches every line)")
    end

    it "sets regex_compile_failed for invalid regex patterns" do
      yaml_str = <<-YAML
        type: "regex"
        patterns:
          - "[unterminated"
        condition: "or"
        YAML
      yaml = YAML.parse(yaml_str)
      matcher = PassiveScan::Matcher.new(yaml)

      matcher.regex_compile_failed?.should be_true
      matcher.compiled_regex.should be_nil
    end
  end

  describe "PassiveScan" do
    it "initializes complete scan from YAML" do
      yaml_str = <<-YAML
        id: "test-scan-001"
        info:
          name: "Test Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference:
            - "https://example.com"
        matchers-condition: "and"
        matchers:
          - type: "regex"
            patterns:
              - "test.*pattern"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.id.should eq("test-scan-001")
      scan.info.name.should eq("Test Rule")
      scan.matchers_condition.should eq("and")
      scan.matchers.size.should eq(1)
      scan.category.should eq("security")
      scan.techs.size.should eq(1)
      scan.valid?.should be_true
    end

    it "defaults missing matchers-condition to 'or'" do
      yaml_str = <<-YAML
        id: "test-single-matcher"
        info:
          name: "Single Matcher Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference: []
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.matchers_condition.should eq("or")
      scan.valid?.should be_true
    end

    it "rejects a rule with no declared severity, naming the field" do
      yaml_str = <<-YAML
        id: "test-default-sev"
        info:
          name: "Default Severity Rule"
          author: []
          description: ""
          reference: []
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs: []
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      # A rule that declares no severity cannot be filtered meaningfully:
      # the default `--passive-scan-severity` threshold is `high`, so any
      # default the loader picked below that would drop the rule from every
      # report without saying so. Rejecting it at load is the visible
      # failure — `load_rules` warns and the count excludes it.
      scan.info.severity.should eq("")
      scan.valid?.should be_false
      scan.validation_errors.should contain("missing 'info.severity' (expected critical, high, medium, low)")
    end

    it "normalizes uppercase matchers-condition to lowercase" do
      yaml_str = <<-YAML
        id: "test-upper-condition"
        info:
          name: "Upper Condition Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference: []
        matchers-condition: "AND"
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "OR"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.matchers_condition.should eq("and")
      scan.matchers[0].condition.should eq("or")
      scan.valid?.should be_true
    end

    it "validates valid scan" do
      yaml_str = <<-YAML
        id: "test-scan-001"
        info:
          name: "Test Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference:
            - "https://example.com"
        matchers-condition: "and"
        matchers:
          - type: "regex"
            patterns:
              - "test.*pattern"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_true
    end

    it "rejects scan with unrecognized severity" do
      yaml_str = <<-YAML
        id: "test-bad-sev"
        info:
          name: "Bad Severity Rule"
          author: []
          severity: "unknown_level"
          description: ""
          reference: []
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs: []
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_false
      scan.validation_errors.should contain("invalid severity \"unknown_level\" (expected critical, high, medium, low)")
    end

    it "rejects scan with invalid matcher type (e.g. keyword)" do
      yaml_str = <<-YAML
        id: "test-invalid-type"
        info:
          name: "Invalid Type Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference: []
        matchers:
          - type: "keyword"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_false
      scan.validation_errors.should contain("matcher[0]: invalid type \"keyword\" (expected 'word' or 'regex')")
    end

    it "rejects scan with invalid matchers-condition" do
      yaml_str = <<-YAML
        id: "test-invalid-condition"
        info:
          name: "Invalid Condition Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference: []
        matchers-condition: "invalid"
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_false
      scan.validation_errors.should contain("invalid matchers-condition \"invalid\" (expected 'and' or 'or')")
    end

    it "rejects scan with empty id" do
      yaml_str = <<-YAML
        id: ""
        info:
          name: "Test Rule"
          author: []
          severity: "high"
          description: ""
          reference: []
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs: []
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_false
      scan.validation_errors.should contain("missing or empty 'id'")
    end

    it "rejects scan with empty info name" do
      yaml_str = <<-YAML
        id: "test-id"
        info:
          name: ""
          author: []
          severity: "high"
          description: ""
          reference: []
        matchers:
          - type: "word"
            patterns:
              - "secret"
            condition: "or"
        category: "security"
        techs: []
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_false
      scan.validation_errors.should contain("missing or empty 'info.name'")
    end

    it "rejects scan with empty matchers" do
      yaml_str = <<-YAML
        id: "test-id"
        info:
          name: "Test Rule"
          author: []
          severity: "high"
          description: ""
          reference: []
        matchers: []
        category: "security"
        techs: []
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      scan.valid?.should be_false
      scan.validation_errors.should contain("missing or empty 'matchers'")
    end
  end

  describe "PassiveScanResult" do
    it "initializes from PassiveScan" do
      yaml_str = <<-YAML
        id: "test-scan-001"
        info:
          name: "Test Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference:
            - "https://example.com"
        matchers-condition: "and"
        matchers:
          - type: "regex"
            patterns:
              - "test.*pattern"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      result = PassiveScanResult.new(
        scan,
        "/path/to/file.js",
        42,
        "const password = 'test123'"
      )

      result.id.should eq("test-scan-001")
      result.info.name.should eq("Test Rule")
      result.category.should eq("security")
      result.file_path.should eq("/path/to/file.js")
      result.line_number.should eq(42)
      result.extract.should eq("const password = 'test123'")
    end

    it "serializes to JSON" do
      yaml_str = <<-YAML
        id: "test-scan-001"
        info:
          name: "Test Rule"
          author:
            - "Test Author"
          severity: "high"
          description: "Test description"
          reference:
            - "https://example.com"
        matchers-condition: "and"
        matchers:
          - type: "regex"
            patterns:
              - "test.*pattern"
            condition: "or"
        category: "security"
        techs:
          - "javascript"
        YAML
      yaml = YAML.parse(yaml_str)
      scan = PassiveScan.new(yaml)

      result = PassiveScanResult.new(scan, "/test.js", 1, "test")
      json = result.to_json

      json.should contain("test-scan-001")
      json.should contain("/test.js")
    end
  end
end
