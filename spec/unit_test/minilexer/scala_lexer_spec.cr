require "spec"
require "../../../src/minilexers/scala_lexer"

describe Noir::ScalaLexer do
  describe "masked and code views" do
    it "blanks strings and nested comments while preserving length and newlines" do
      source = <<-SCALA
        // phantom("line")
        /* outer /* phantom("nested") */ still a comment */
        val doc = """
          path("phantom") { get { complete("x") } }
        """
        val c = 'x'
        path("real") { get { complete("y") } }
        SCALA

      lexer = Noir::ScalaLexer.new(source)
      masked = lexer.masked.join
      code = lexer.code.join

      masked.size.should eq(source.size)
      masked.count('\n').should eq(source.count('\n'))
      masked.should_not contain("phantom")
      masked.should_not contain("real")
      code.should_not contain("phantom")
      code.should contain("path(\"real\")")
      lexer.in_code?(source.index!("phantom")).should be_false
      lexer.in_code?(source.index!("path(\"real\")")).should be_true
    end

    it "keeps masked and code line counts aligned with the source" do
      source = "val a = 1\n/* comment\n * continued */\nval b = \"text\"\n"
      lexer = Noir::ScalaLexer.new(source)

      lexer.masked_lines.size.should eq(source.lines.size)
      lexer.code_lines.size.should eq(source.lines.size)
      lexer.masked_lines[1].should_not contain("comment")
      lexer.code_lines[3].should contain("val b")
    end
  end

  describe "matching_delimiter" do
    it "matches nested parentheses, brackets, and braces" do
      source = "call([item({value})])"
      lexer = Noir::ScalaLexer.new(source)

      lexer.matching_delimiter(source.index!('(')).should eq(source.rindex!(')'))
      lexer.matching_delimiter(source.index!('[')).should eq(source.rindex!(']'))
      lexer.matching_delimiter(source.index!('{')).should eq(source.index!('}'))
    end

    it "ignores delimiters inside strings and comments" do
      source = "val text = \"{ not code }\" /* ( not code ) */ { real }"
      lexer = Noir::ScalaLexer.new(source)
      open_pos = source.rindex!('{')
      close_pos = source.rindex!('}')

      lexer.matching_delimiter(open_pos).should eq(close_pos)
      lexer.matching_delimiter(source.index!('{')).should be_nil
      lexer.matching_delimiter(source.index!('(')).should be_nil
      lexer.matching_delimiter(0).should be_nil
    end

    it "returns nil for an unbalanced delimiter" do
      lexer = Noir::ScalaLexer.new("call(value")

      lexer.matching_delimiter(lexer.masked.index!('(')).should be_nil
    end
  end

  describe "statement_end" do
    it "stops at a top-level semicolon" do
      source = "call(a; b); next"
      lexer = Noir::ScalaLexer.new(source)
      first = source.index!(';')
      second = source.index!(';', first + 1)

      lexer.statement_end(0).should eq(second + 1)
    end

    it "ignores semicolons nested in brackets and returns the source size when absent" do
      source = "call([a; b])"
      lexer = Noir::ScalaLexer.new(source)

      lexer.statement_end(0).should eq(source.size)
    end
  end

  describe "tokens" do
    it "reports token kind, value, character range, and one-based line" do
      source = "val path = \"/users\"\npath(\"/items\")"
      tokens = Noir::ScalaLexer.new(source).tokens

      tokens.map(&.kind).should eq([:ident, :ident, :string, :ident, :lparen, :string, :rparen])
      tokens[0].value.should eq("val")
      tokens[2].value.should eq("\"/users\"")
      tokens[2].start.should eq(source.index!('"'))
      tokens[2].end.should eq(tokens[2].start + tokens[2].value.size)
      tokens[0].line.should eq(1)
      tokens[3].line.should eq(2)
      tokens[-1].line.should eq(2)
    end
  end
end
