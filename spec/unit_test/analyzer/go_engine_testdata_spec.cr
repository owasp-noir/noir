require "../../spec_helper"
require "../../../src/analyzer/engines/go_engine"

describe Analyzer::Go::GoEngine do
  describe ".go_test_file? and testdata/" do
    # `go help packages`: directories named testdata are ignored.
    it "skips a testdata directory at the root or any depth" do
      Analyzer::Go::GoEngine.go_test_file?("/testdata/x.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("/pkg/testdata/a/b.go").should be_true
      Analyzer::Go::GoEngine.go_test_file?("testdata/x.go").should be_true
    end

    it "matches the whole segment only" do
      Analyzer::Go::GoEngine.go_test_file?("/mytestdata/x.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/testdata_x/y.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("/pkg/testdata.go").should be_false
      Analyzer::Go::GoEngine.go_test_file?("testdata.go").should be_false
    end
  end
end
