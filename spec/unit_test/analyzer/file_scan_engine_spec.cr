require "../../spec_helper"
require "../../../src/analyzer/engines/file_scan_engine"

class FileScanEngineSpecHarness < FileScanEngine
  def initialize(options : Hash(String, YAML::Any), @files : Array(String))
    super(options)
  end

  protected def scan_target_files : Array(String)
    @files
  end

  def analyze_file(path : String) : Array(Endpoint)
    # Make the first file finish after the rest, so the test distinguishes
    # source order from worker completion order.
    sleep 20.milliseconds if path == "file-0"
    [Endpoint.new("/#{path}", "GET")]
  end
end

describe FileScanEngine do
  it "merges per-file results on the caller fiber in input order" do
    options = create_test_options
    options["concurrency"] = YAML::Any.new("8")
    files = (0...8).map { |index| "file-#{index}" }

    endpoints = FileScanEngineSpecHarness.new(options, files).analyze

    endpoints.map(&.url).should eq(files.map { |path| "/#{path}" })
  end
end
