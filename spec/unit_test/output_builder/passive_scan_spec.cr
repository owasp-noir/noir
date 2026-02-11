require "../../spec_helper"
require "../../../src/output_builder/passive_scan"
require "../../../src/models/passive_scan"
require "../../../src/models/logger"
require "../../../src/utils/utils"
require "yaml"

# Mock logger to capture output
class MockLogger < NoirLogger
  property io : IO::Memory

  def initialize
    @io = IO::Memory.new
    # Initialize NoirLogger with default values (false for debug, verbose, color, nolog)
    super(false, false, false, false)
  end

  def puts(message)
    @io.puts message
  end

  def sub(message)
    @io.puts "  " + message
  end
end

describe "OutputBuilderPassiveScan" do
  describe "#severity_color" do
    it "returns colored string for critical severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      })

      builder.severity_color("critical").should contain("critical")
    end

    it "returns colored string for high severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      })
      builder.severity_color("high").should contain("high")
    end

    it "returns colored string for medium severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      })
      builder.severity_color("medium").should contain("medium")
    end

    it "returns colored string for low severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      })
      builder.severity_color("low").should contain("low")
    end

    it "returns colored string for info severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      })
      builder.severity_color("info").should contain("info")
    end

    it "returns colored string for unknown severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      })
      builder.severity_color("unknown").should contain("unknown")
    end
  end

  describe "#print" do
    it "prints passive scan results correctly" do
      options = {
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      }
      builder = OutputBuilderPassiveScan.new(options)
      logger = MockLogger.new

      scan_yaml = YAML.parse <<-YAML
        id: test-rule
        info:
          name: "Test Rule Name"
          author: ["test-author"]
          severity: "high"
          description: "Test Description"
          reference: ["https://example.com"]
        matchers-condition: "or"
        matchers:
          - type: "regex"
            patterns: ["test"]
            condition: "or"
        category: "secret"
        techs: ["*"]
        YAML
      passive_scan = PassiveScan.new(scan_yaml)
      passive_result = PassiveScanResult.new(
        passive_scan,
        "src/test.cr",
        15,
        "found secret"
      )

      builder.print([passive_result], logger, false)

      output = logger.io.to_s
      output.should contain("[high]")
      output.should contain("[test-rule]")
      output.should contain("[secret]")
      output.should contain("Test Rule Name")
      output.should contain("├── extract: found secret")
      output.should contain("└── file: src/test.cr:15")
    end

    it "prints multiple passive scan results" do
      options = {
        "debug" => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color" => YAML::Any.new(false),
        "nolog" => YAML::Any.new(false),
        "output" => YAML::Any.new("")
      }
      builder = OutputBuilderPassiveScan.new(options)
      logger = MockLogger.new

      scan_yaml1 = YAML.parse <<-YAML
        id: rule-1
        info:
          name: "Rule 1"
          author: ["author1"]
          severity: "critical"
          description: "Desc 1"
          reference: [""]
        matchers-condition: "or"
        matchers:
          - type: "regex"
            patterns: ["test1"]
            condition: "or"
        category: "cat1"
        techs: ["*"]
        YAML

      scan_yaml2 = YAML.parse <<-YAML
        id: rule-2
        info:
          name: "Rule 2"
          author: ["author2"]
          severity: "low"
          description: "Desc 2"
          reference: [""]
        matchers-condition: "or"
        matchers:
          - type: "regex"
            patterns: ["test2"]
            condition: "or"
        category: "cat2"
        techs: ["*"]
        YAML

      result1 = PassiveScanResult.new(PassiveScan.new(scan_yaml1), "file1.cr", 1, "extract1")
      result2 = PassiveScanResult.new(PassiveScan.new(scan_yaml2), "file2.cr", 2, "extract2")

      builder.print([result1, result2], logger, false)

      output = logger.io.to_s
      output.should contain("Rule 1")
      output.should contain("file1.cr:1")
      output.should contain("Rule 2")
      output.should contain("file2.cr:2")
    end
  end
end
