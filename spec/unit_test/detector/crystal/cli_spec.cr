require "../../../spec_helper"
require "../../../../src/detector/detectors/crystal/*"

describe "Detect Crystal CLI" do
  options = create_test_options
  instance = Detector::Crystal::Cli.new options

  it "ARGV.first? / ARGV.shift?" do
    instance.detect("tool.cr", "command = ARGV.first?").should be_true
    instance.detect("tool.cr", "case ARGV.shift?\nwhen \"add\"\nend").should be_true
  end

  it "ARGV compared to an array" do
    instance.detect("tool.cr", "dry_run = ARGV == [\"--dry-run\"]").should be_true
  end

  it "ARGV as a default argument is not a read" do
    instance.detect("server.cr", "def run(port, args = ARGV)\nend").should be_false
  end
end
