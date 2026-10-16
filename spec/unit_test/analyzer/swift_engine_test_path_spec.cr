require "../../spec_helper"
require "../../../src/analyzer/engines/swift_engine"

describe Analyzer::Swift::SwiftEngine do
  describe ".swift_test_path?" do
    it "skips the SwiftPM test and package-benchmark directories" do
      Analyzer::Swift::SwiftEngine.swift_test_path?("/Tests/AppTests/RoutesTests.swift").should be_true
      Analyzer::Swift::SwiftEngine.swift_test_path?("/Benchmarks/Foo/Benchmarks.swift").should be_true
    end

    it "keeps application sources" do
      Analyzer::Swift::SwiftEngine.swift_test_path?("/Sources/App/routes.swift").should be_false
      Analyzer::Swift::SwiftEngine.swift_test_path?("/Sources/App/Controllers/BenchmarksController.swift").should be_false
    end

    it "keeps a Benchmarks directory that is not at the package root" do
      Analyzer::Swift::SwiftEngine.swift_test_path?("/Sources/App/Controllers/Benchmarks/BenchmarkController.swift").should be_false
      Analyzer::Swift::SwiftEngine.swift_test_path?("/pkg/Benchmarks/Foo/EndToEnd.swift").should be_false
    end
  end
end
