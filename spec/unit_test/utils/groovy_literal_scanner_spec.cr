require "spec"
require "../../../src/utils/groovy_literal_scanner"

private def expect_remaining(content : String, result : Int32?, expected : String)
  result.should_not be_nil
  if index = result
    content[index..].should eq(expected)
  end
end

describe Noir::GroovyLiteralScanner do
  describe "skip_literal" do
    context "single-line strings" do
      it "skips a double-quoted string" do
        content = %("hello" world)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        result.should eq(7)
        expect_remaining(content, result, " world")
      end

      it "skips a single-quoted string" do
        content = %('hello' world)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        result.should eq(7)
        expect_remaining(content, result, " world")
      end

      it "handles escaped quotes in double-quoted strings" do
        content = %("a\\"b" tail)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        result.should eq(6)
        expect_remaining(content, result, " tail")
      end

      it "handles escaped quotes in single-quoted strings" do
        content = %('a\\'b' tail)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        result.should eq(6)
        expect_remaining(content, result, " tail")
      end

      it "returns content size for an unterminated quoted string" do
        content = %("never ends)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        result.should eq(content.size)
      end
    end

    context "triple-quoted strings" do
      it "skips a triple double-quoted string" do
        content = %("""line1\nline2""" tail)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        expect_remaining(content, result, " tail")
      end

      it "skips a triple single-quoted string" do
        content = %('''multi\nline''' tail)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        expect_remaining(content, result, " tail")
      end

      it "treats triple quote with single inner quote as still inside the literal" do
        content = %("""has " inside""" tail)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        expect_remaining(content, result, " tail")
      end

      it "respects an escaped closing triple quote" do
        # The third quote is escaped, so the literal continues past it.
        content = %("""a\\""" still""" tail)
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        expect_remaining(content, result, " tail")
      end
    end

    context "slashy regex literals" do
      it "skips a slashy literal after an opening paren" do
        content = "matches(/foo/, x)"
        # '/' is at index 8
        result = Noir::GroovyLiteralScanner.skip_literal(content, 8)
        result.should eq(13)
        expect_remaining(content, result, ", x)")
      end

      it "skips a slashy literal after a keyword (return)" do
        content = "return /abc/"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 7)
        result.should eq(content.size)
      end

      it "skips a slashy literal after the 'case' keyword" do
        content = "case /abc/:"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 5)
        result.should eq(10)
        expect_remaining(content, result, ":")
      end

      it "honors escaped slashes inside a slashy literal" do
        content = "= /a\\/b/ tail"
        # '/' that starts the regex is at index 2
        result = Noir::GroovyLiteralScanner.skip_literal(content, 2)
        result.should eq(8)
        expect_remaining(content, result, " tail")
      end

      it "does not treat // as a slashy literal start" do
        content = "= // comment"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 2)
        result.should be_nil
      end

      it "does not treat /* as a slashy literal start" do
        content = "= /* block */"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 2)
        result.should be_nil
      end

      it "does not treat /= as a slashy literal start" do
        content = "x /= 2"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 2)
        result.should be_nil
      end

      it "treats '/' after an identifier as division (returns nil)" do
        content = "x / y"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 2)
        result.should be_nil
      end

      it "treats '/' at the start of input as a slashy literal" do
        content = "/abc/"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 0)
        result.should eq(5)
      end
    end

    context "dollar-slashy literals" do
      it "skips a basic dollar-slashy literal" do
        content = "x = $/regex with /slash/$ tail"
        # '$' is at index 4
        result = Noir::GroovyLiteralScanner.skip_literal(content, 4)
        expect_remaining(content, result, " tail")
      end

      it "respects an escaped closing delimiter ($/) in dollar-slashy" do
        # The first /$ is preceded by '$', meaning it's escaped per the module's rule.
        content = "x = $/foo$/$ still/$ tail"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 4)
        expect_remaining(content, result, " tail")
      end

      it "returns content size for unterminated dollar-slashy" do
        content = "x = $/never closes"
        result = Noir::GroovyLiteralScanner.skip_literal(content, 4)
        result.should eq(content.size)
      end
    end

    context "non-literal positions" do
      it "returns nil for an arbitrary identifier character" do
        Noir::GroovyLiteralScanner.skip_literal("name", 0).should be_nil
      end

      it "returns nil when pos is out of bounds" do
        Noir::GroovyLiteralScanner.skip_literal("abc", 10).should be_nil
      end

      it "returns nil for a standalone '$' that is not followed by '/'" do
        Noir::GroovyLiteralScanner.skip_literal("$foo", 0).should be_nil
      end
    end
  end
end
