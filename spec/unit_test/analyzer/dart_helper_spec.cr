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

  describe ".extract_string_literal" do
    it "reads single and double quoted literals" do
      Analyzer::Dart::Helper.extract_string_literal(%('/webhook')).should eq("/webhook")
      Analyzer::Dart::Helper.extract_string_literal(%(  "/index.html"  )).should eq("/index.html")
    end

    it "returns nil for non-literal expressions" do
      Analyzer::Dart::Helper.extract_string_literal("RouteRoot()").should be_nil
    end
  end

  describe ".find_matching_paren" do
    it "returns the index of the balancing paren" do
      text = "get('/a', handler)"
      Analyzer::Dart::Helper.find_matching_paren(text, 3).should eq(text.size - 1)
    end

    it "skips nested calls" do
      text = "get(join('/a', '/b'), handler)"
      Analyzer::Dart::Helper.find_matching_paren(text, 3).should eq(text.size - 1)
    end

    it "ignores parens inside string literals" do
      # The `)` in the path literal must not close the call.
      text = "get('/a)b', handler)"
      Analyzer::Dart::Helper.find_matching_paren(text, 3).should eq(text.size - 1)
    end

    it "honours backslash escapes inside literals" do
      # Dart source: get('it\'s )', h) — the escaped quote must not end the
      # literal, so the `)` inside it must not close the call either.
      text = "get('it\\'s )', h)"
      Analyzer::Dart::Helper.find_matching_paren(text, 3).should eq(text.size - 1)
    end

    it "returns char indices on multi-byte sources" do
      text = "get('한글', handler)"
      Analyzer::Dart::Helper.find_matching_paren(text, 3).should eq(text.size - 1)
    end

    it "returns nil when the expression never balances" do
      Analyzer::Dart::Helper.find_matching_paren("get('/a', handler", 3).should be_nil
    end

    it "does not re-read the whole file per call" do
      # One call per route used to materialise `text.chars` for the whole
      # file, so a large route file was O(routes x file). (Multi-byte
      # source still pays an O(offset) char-to-byte walk per call.)
      text = (0...2000).map { |i| "router.post('/r#{i}', (Request req) => ok(req));\n" }.join
      opens = [] of Int32
      text.scan(/router\.post\(/) { |m| opens << m.end(0).not_nil! - 1 }
      closes = [] of Int32?
      elapsed = Time.measure do
        opens.each do |open|
          close = Analyzer::Dart::Helper.find_matching_paren(text, open)
          closes << close
          Analyzer::Dart::Helper.first_top_level_comma(text, open + 1, close.not_nil!)
        end
      end
      closes.compact.size.should eq(2000)
      text[closes.last.not_nil!].should eq(')')
      elapsed.should be < 2.seconds
    end
  end

  describe ".first_top_level_comma" do
    it "returns char indices past multi-byte literals and nested args" do
      text = "get('한,글', f(a, b), handler)"
      comma = Analyzer::Dart::Helper.first_top_level_comma(text, 4, text.size - 1)
      comma.should eq(text.index(", f"))
    end

    it "stops at the limit and skips escaped quotes" do
      text = "get('it\\'s, x', h)"
      Analyzer::Dart::Helper.first_top_level_comma(text, 4, text.size - 1).should eq(text.index(", h"))
      Analyzer::Dart::Helper.first_top_level_comma(text, 4, 8).should be_nil
    end
  end

  describe Analyzer::Dart::Helper::LineIndex do
    it "matches line_number_for_index on multi-byte source" do
      content = "한글\nget('/a')\n\n  é post('/b')\n"
      index = Analyzer::Dart::Helper::LineIndex.new(content)
      [-1, 0, 1, 2, 3, 4, 13, 14, 15, 18, content.size, content.size + 5].each do |pos|
        expected = 1 + content.each_char.first(pos.clamp(0, content.size)).count('\n')
        index.line_for(pos).should eq(expected)
      end
    end
  end
end
