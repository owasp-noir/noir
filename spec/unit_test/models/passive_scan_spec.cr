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
