require "../../spec_helper"
require "../../../src/analyzer/analyzers/dart/dart_helper"

describe Analyzer::Dart::Helper do
  describe ".test_path?" do
    it "flags Dart Frog test/routes mirror trees" do
      Analyzer::Dart::Helper.test_path?("/repo/backend/test/routes/index_test.dart", "/repo/backend").should be_true
    end

    it "flags the standard test/ directory and *_test.dart suffix" do
      Analyzer::Dart::Helper.test_path?("/repo/test/integration/pay_endpoint_test.dart", "/repo").should be_true
      Analyzer::Dart::Helper.test_path?("/repo/lib/widget_test.dart", "/repo").should be_true
    end

    it "does not flag production route files" do
      Analyzer::Dart::Helper.test_path?("/repo/routes/api/blogs/index.dart", "/repo").should be_false
      Analyzer::Dart::Helper.test_path?("/repo/lib/src/endpoints/order_endpoint.dart", "/repo").should be_false
    end

    it "does not treat a base path containing 'test' as a test tree" do
      Analyzer::Dart::Helper.test_path?("/tmp/test_app/routes/index.dart", "/tmp/test_app").should be_false
    end

    it "uses the most specific base path when base paths overlap" do
      Analyzer::Dart::Helper.test_path?("/repo/mono/test/routes/index.dart", ["/repo/mono", "/repo/mono/test"]).should be_false
    end
  end

  describe ".strip_comments" do
    it "blanks line and block comments but keeps strings and offsets" do
      source = %(final x = 1; // note\nfinal s = "a // b"; /* c */ final y = 2;)
      stripped = Analyzer::Dart::Helper.strip_comments(source)
      stripped.bytesize.should eq source.bytesize
      stripped.includes?("note").should be_false
      stripped.includes?("/* c */").should be_false
      stripped.includes?("a // b").should be_true
    end
  end

  describe ".extract_string_literal" do
    it "reads single and double quoted literals" do
      Analyzer::Dart::Helper.extract_string_literal(%('/webhook')).should eq("/webhook")
      Analyzer::Dart::Helper.extract_string_literal(%(  "/index.html"  )).should eq("/index.html")
    end

    it "returns nil for non-literal expressions" do
      Analyzer::Dart::Helper.extract_string_literal("RouteRoot()").should be_nil
    end
  end
end
