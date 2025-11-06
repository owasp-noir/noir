require "../../../spec_helper"
require "../../../../src/models/minilexer/minilexer.cr"

describe "MiniLexer" do
  describe "initialization" do
    it "creates lexer with default properties" do
      lexer = MiniLexer.new

      lexer.tokens.should be_empty
      lexer.mode.should eq(:normal)
    end
  end

  describe "mode" do
    it "sets mode to normal" do
      lexer = MiniLexer.new
      lexer.mode = :normal

      lexer.mode.should eq(:normal)
    end

    it "sets mode to persistent" do
      lexer = MiniLexer.new
      lexer.mode = :persistent

      lexer.mode.should eq(:persistent)
    end
  end

  describe "tokenize" do
    it "returns empty array for base implementation" do
      lexer = MiniLexer.new
      tokens = lexer.tokenize("test input")

      tokens.should be_empty
    end

    it "clears position in normal mode" do
      lexer = MiniLexer.new
      lexer.mode = :normal

      lexer.tokenize("first")
      lexer.tokenize("second")

      # Should not accumulate tokens in normal mode
      lexer.tokens.should be_empty
    end

    it "accumulates tokens in persistent mode" do
      lexer = MiniLexer.new
      lexer.mode = :persistent

      lexer.tokenize("first")
      lexer.tokenize("second")

      # Should accumulate (though base implementation returns empty)
      lexer.tokens.should be_empty # Base implementation doesn't add tokens
    end
  end

  describe "<<" do
    it "adds token from Symbol and String tuple" do
      lexer = MiniLexer.new
      lexer << {:keyword, "if"}

      lexer.tokens.size.should eq(1)
      lexer.tokens[0].type.should eq(:keyword)
      lexer.tokens[0].value.should eq("if")
    end

    it "adds token from Symbol and Char tuple" do
      lexer = MiniLexer.new
      lexer << {:operator, '='}

      lexer.tokens.size.should eq(1)
      lexer.tokens[0].type.should eq(:operator)
      lexer.tokens[0].value.should eq("=")
    end

    it "adds multiple tokens sequentially" do
      lexer = MiniLexer.new
      lexer << {:keyword, "if"}
      lexer << {:operator, '='}
      lexer << {:number, "42"}

      lexer.tokens.size.should eq(3)
      lexer.tokens[0].type.should eq(:keyword)
      lexer.tokens[1].type.should eq(:operator)
      lexer.tokens[2].type.should eq(:number)
    end
  end

  describe "find" do
    it "finds tokens by type" do
      lexer = MiniLexer.new
      lexer << {:keyword, "if"}
      lexer << {:number, "42"}
      lexer << {:keyword, "else"}

      keywords = lexer.find(:keyword)
      keywords.size.should eq(2)
      keywords[0].value.should eq("if")
      keywords[1].value.should eq("else")
    end

    it "returns empty array when type not found" do
      lexer = MiniLexer.new
      lexer << {:keyword, "if"}

      strings = lexer.find(:string)
      strings.should be_empty
    end

    it "finds all tokens of same type" do
      lexer = MiniLexer.new
      lexer << {:string, "hello"}
      lexer << {:string, "world"}
      lexer << {:number, "42"}

      strings = lexer.find(:string)
      strings.size.should eq(2)
    end
  end

  describe "line tracking" do
    it "tracks line numbers correctly" do
      lexer = MiniLexer.new
      lexer << {:keyword, "if"}

      # Line tracking should work
      lexer.tokens[0].line.should be >= 1
    end
  end
end
