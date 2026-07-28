require "../../spec_helper"
require "../../../src/output_builder/passive_scan"
require "../../../src/models/passive_scan"
require "../../../src/models/logger"
require "../../../src/utils/utils"
require "yaml"

# Stands in for a stdout whose reader has gone away (`noir ... -P | head`).
# Writing raises the same EPIPE `IO::Error` the runtime would, which is
# what `OutputBuilder#ob_puts` inspects before deciding to abandon stdout
# and keep writing the `-o` file.
class BrokenPipeIO < IO
  def read(slice : Bytes) : Int32
    0
  end

  def write(slice : Bytes) : Nil
    raise IO::Error.from_os_error("write", Errno::EPIPE)
  end
end

describe "OutputBuilderPassiveScan" do
  describe "#severity_color" do
    it "returns colored string for critical severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      })

      builder.severity_color("critical").should contain("critical")
    end

    it "returns colored string for high severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      })
      builder.severity_color("high").should contain("high")
    end

    it "returns colored string for medium severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      })
      builder.severity_color("medium").should contain("medium")
    end

    it "returns colored string for low severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      })
      builder.severity_color("low").should contain("low")
    end

    it "returns colored string for info severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      })
      builder.severity_color("info").should contain("info")
    end

    it "returns colored string for unknown severity" do
      builder = OutputBuilderPassiveScan.new({
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      })
      builder.severity_color("unknown").should contain("unknown")
    end
  end

  describe "#print" do
    it "prints passive scan results correctly" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderPassiveScan.new(options)
      io = IO::Memory.new
      builder.io = io

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

      builder.print([passive_result])

      # The whole finding has to land on the report stream, in order.
      # `noir scan . -P > findings.txt` once kept the rule header and lost
      # the extract and the file:line that say where the secret actually
      # is, because those two went to stderr. Asserting the exact block
      # rather than the presence of each piece is what catches a line
      # drifting back off this stream.
      io.to_s.should eq(<<-REPORT)
        [high][test-rule][secret] Test Rule Name
          ├── extract: found secret
          └── file: src/test.cr:15\n\n
        REPORT
    end

    # `-P` findings used to reach stdout only, so `noir scan . -P -o
    # report.txt` saved the endpoint list without the secrets the scan was
    # run to find.
    it "writes findings to the output file as well as stdout" do
      output_file = File.tempname("noir-passive-scan-output")

      begin
        options = {
          "debug"   => YAML::Any.new(false),
          "verbose" => YAML::Any.new(false),
          "color"   => YAML::Any.new(false),
          "nolog"   => YAML::Any.new(false),
          "output"  => YAML::Any.new(output_file),
        }
        builder = OutputBuilderPassiveScan.new(options)
        io = IO::Memory.new
        builder.io = io

        scan_yaml = YAML.parse <<-YAML
          id: leaky-rule
          info:
            name: "Leaky Rule"
            author: ["test-author"]
            severity: "critical"
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
        result = PassiveScanResult.new(PassiveScan.new(scan_yaml), "src/leak.cr", 7, "hunter2")

        builder.print([result])

        # "as well as": the file gaining the findings must not cost stdout
        # its copy, so both halves are asserted.
        written = File.read(output_file)
        written.should contain("[leaky-rule]")
        written.should contain("├── extract: hunter2")
        written.should contain("└── file: src/leak.cr:7")

        io.to_s.should eq(written)
      ensure
        NoirOutputFiles.reset
        File.delete(output_file) if File.exists?(output_file)
      end
    end

    it "prints multiple passive scan results" do
      options = {
        "debug"   => YAML::Any.new(false),
        "verbose" => YAML::Any.new(false),
        "color"   => YAML::Any.new(false),
        "nolog"   => YAML::Any.new(false),
        "output"  => YAML::Any.new(""),
      }
      builder = OutputBuilderPassiveScan.new(options)
      io = IO::Memory.new
      builder.io = io

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

      builder.print([result1, result2])

      output = io.to_s
      output.should contain("Rule 1")
      output.should contain("file1.cr:1")
      output.should contain("Rule 2")
      output.should contain("file2.cr:2")
    end

    # `noir scan . -P -o report.txt | head` must still save a complete
    # report. This pins the builder half — `ob_puts` giving up on stdout
    # and carrying on with the file. The other half, `NoirRunner#print_
    # passive_results` emitting its separator through `ob_puts` rather than
    # `NoirLogger#puts` (which `exit(0)`s the whole process on EPIPE), can
    # only be reached with a genuinely broken STDOUT and is covered by
    # running the built binary under a closed pipe, not from here.
    it "keeps filling the output file after stdout's reader closes the pipe" do
      output_file = File.tempname("noir-passive-scan-epipe")

      begin
        options = {
          "debug"   => YAML::Any.new(false),
          "verbose" => YAML::Any.new(false),
          "color"   => YAML::Any.new(false),
          "nolog"   => YAML::Any.new(false),
          "output"  => YAML::Any.new(output_file),
        }
        builder = OutputBuilderPassiveScan.new(options)
        builder.io = BrokenPipeIO.new

        scan_yaml = YAML.parse <<-YAML
          id: piped-rule
          info:
            name: "Piped Rule"
            author: ["test-author"]
            severity: "critical"
            description: "Test Description"
            reference: [""]
          matchers-condition: "or"
          matchers:
            - type: "regex"
              patterns: ["test"]
              condition: "or"
          category: "secret"
          techs: ["*"]
          YAML
        result = PassiveScanResult.new(PassiveScan.new(scan_yaml), "src/piped.cr", 3, "swordfish")

        builder.print([result])

        written = File.read(output_file)
        written.should contain("[piped-rule]")
        written.should contain("├── extract: swordfish")
        written.should contain("└── file: src/piped.cr:3")
      ensure
        NoirOutputFiles.reset
        File.delete(output_file) if File.exists?(output_file)
      end
    end
  end
end
