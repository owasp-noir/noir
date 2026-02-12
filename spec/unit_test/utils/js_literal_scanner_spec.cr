require "spec"
require "../../../src/utils/js_literal_scanner"

describe Noir::JSLiteralScanner do
  describe "extract_paren_content" do
    it "extracts simple content" do
      result = Noir::JSLiteralScanner.extract_paren_content("(hello)", 1)
      result.should_not be_nil
      if result
        result.content.should eq("hello")
        result.end_pos.should eq(6) # Position OF closing paren
      end
    end

    it "handles nested parentheses" do
      result = Noir::JSLiteralScanner.extract_paren_content("(hello(world))", 1)
      result.should_not be_nil
      if result
        result.content.should eq("hello(world)")
        result.end_pos.should eq(13)
      end
    end

    it "ignores parentheses inside strings" do
      result = Noir::JSLiteralScanner.extract_paren_content("('hello(world)')", 1)
      result.should_not be_nil
      if result
        result.content.should eq("'hello(world)'")
        result.end_pos.should eq(15)
      end
    end

    it "ignores parentheses inside comments" do
      # Comments are stripped from the extracted content
      result = Noir::JSLiteralScanner.extract_paren_content("(// (hello)\n)", 1)
      result.should_not be_nil
      if result
        result.content.should eq("\n")
        result.end_pos.should eq(12)
      end
    end

    it "handles complex nested structures" do
      content = "({a: (1+2), b: \"(str)\"})"
      result = Noir::JSLiteralScanner.extract_paren_content(content, 1)
      result.should_not be_nil
      if result
        result.content.should eq("{a: (1+2), b: \"(str)\"}")
        result.end_pos.should eq(23)
      end
    end

    it "returns what it found if parentheses are unbalanced" do
      # If end of string reached, it returns what was collected
      result = Noir::JSLiteralScanner.extract_paren_content("(unbalanced", 1)
      result.should_not be_nil
      if result
        result.content.should eq("unbalanced")
        result.end_pos.should eq(11)
      end
    end
  end

  describe "try_skip_literal" do
    it "skips single-line comments" do
      content = "// comment\nnext"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 0, "")
      res.should_not be_nil
      if res
        res[:content].should eq("")
        res[:pos].should eq(10) # Position of newline
        content[res[:pos]..].should start_with("\nnext")
      end
    end

    it "skips multi-line comments" do
      content = "/* comment */next"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 0, "")
      res.should_not be_nil
      if res
        res[:content].should eq("")
        res[:pos].should eq(13)
        content[res[:pos]..].should eq("next")
      end
    end

    it "skips double-quoted strings" do
      content = "\"string\"next"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 0, "")
      res.should_not be_nil
      if res
        res[:content].should eq("\"string\"")
        res[:pos].should eq(8)
        content[res[:pos]..].should eq("next")
      end
    end

    it "skips single-quoted strings" do
      content = "'string'next"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 0, "")
      res.should_not be_nil
      if res
        res[:content].should eq("'string'")
        res[:pos].should eq(8)
        content[res[:pos]..].should eq("next")
      end
    end

    it "skips escaped quotes in strings" do
      content = "\"str\\\"ing\"next"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 0, "")
      res.should_not be_nil
      if res
        res[:content].should eq("\"str\\\"ing\"")
        res[:pos].should eq(10)
        content[res[:pos]..].should eq("next")
      end
    end

    it "skips template literals" do
      content = "`template`next"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 0, "")
      res.should_not be_nil
      if res
        res[:content].should eq("`template`")
        res[:pos].should eq(10)
        content[res[:pos]..].should eq("next")
      end
    end

    it "skips regex literals" do
      # Context matters for regex vs division
      content = "return /regex/;"
      # "return " is 7 chars. '/' is at 7.
      res = Noir::JSLiteralScanner.try_skip_literal(content, 7, "return ")
      res.should_not be_nil
      if res
        res[:content].should eq("return /regex/")
        res[:pos].should eq(14)
        content[res[:pos]..].should eq(";")
      end
    end

    it "skips regex literals with flags" do
      content = "return /regex/gi;"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 7, "return ")
      res.should_not be_nil
      if res
        res[:content].should eq("return /regex/gi")
        res[:pos].should eq(16)
        content[res[:pos]..].should eq(";")
      end
    end

    it "identifies division operator (not regex)" do
      content = "var a = 10 / 2;"
      # "var a = 10 " ends with a number, so / should be division
      res = Noir::JSLiteralScanner.try_skip_literal(content, 11, "var a = 10 ")
      res.should be_nil
    end

    it "handles regex with character classes" do
      content = "return /[a-z]/;"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 7, "return ")
      res.should_not be_nil
      if res
        res[:content].should eq("return /[a-z]/")
        res[:pos].should eq(14)
      end
    end

    it "handles regex with escaped slashes" do
      content = "return /\\//;"
      res = Noir::JSLiteralScanner.try_skip_literal(content, 7, "return ")
      res.should_not be_nil
      if res
        res[:content].should eq("return /\\//")
        res[:pos].should eq(11)
      end
    end
  end

  describe "find_matching_brace" do
    it "finds matching brace" do
      content = "{ code }"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should eq(7)
    end

    it "handles nested braces" do
      content = "{ { code } }"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should eq(11)
    end

    it "ignores braces in strings" do
      content = "{ \"}\" }"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should eq(6)
    end

    it "returns nil if not found" do
      content = "{ code"
      idx = Noir::JSLiteralScanner.find_matching_brace(content, 0)
      idx.should be_nil
    end
  end

  describe "find_matching_paren" do
    it "finds matching paren" do
      content = "( code )"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should eq(7)
    end

    it "handles nested parens" do
      content = "( ( code ) )"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should eq(11)
    end

    it "ignores parens in strings" do
      content = "( \")\" )"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should eq(6)
    end

    it "returns nil if not found" do
      content = "( code"
      idx = Noir::JSLiteralScanner.find_matching_paren(content, 0)
      idx.should be_nil
    end
  end
end
