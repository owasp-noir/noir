require "../../spec_helper"
require "../../../src/minilexers/csharp_lexer"

describe Noir::CSharpLexer do
  it "keeps the masked buffer aligned with the source length" do
    src = "var v = @\"a \"\"b\"\" }\"; var r = \"\"\"raw } \"\"\"; c = '}';"
    Noir::CSharpLexer.new(src).masked.size.should eq(src.size)
  end

  describe "string masking" do
    it "blanks a `}` and `(` inside a regular string" do
      src = "var j = T(\"a } b ( c\");"
      m = Noir::CSharpLexer.new(src).masked_lines[0]
      m.count('}').should eq(0)
      m.count('(').should eq(1) # only the real T( paren survives
      m.count(')').should eq(1)
    end

    it "handles verbatim strings (doubled quote escapes, backslash literal)" do
      src = "var p = @\"C:\\temp \"\"q\"\" }x\"; ok();"
      lex = Noir::CSharpLexer.new(src)
      lex.in_code?(src.index!("}x")).should be_false
      lex.in_code?(src.index!("ok")).should be_true
    end

    it "handles interpolated strings including a nested string in a hole" do
      src = "var s = $\"id={foo(\"}\")}-end\"; after();"
      lex = Noir::CSharpLexer.new(src)
      lex.in_code?(src.index!("foo")).should be_false  # inside the interpolation
      lex.in_code?(src.index!("after")).should be_true # the literal ended correctly
    end

    it "skips nested verbatim/raw strings inside an interpolation hole" do
      # The `}` inside the nested `@"…"` / `"""…"""` must not terminate the
      # outer interpolated string early.
      verbatim = "var s = $\"x{Path(@\"a\"\"}\"\"b\")}y\"; tail();"
      Noir::CSharpLexer.new(verbatim).in_code?(verbatim.index!("tail")).should be_true

      raw = "var s = $\"x{F(\"\"\"a}\"\" }\"\"\" )}y\"; done();"
      Noir::CSharpLexer.new(raw).in_code?(raw.index!("done")).should be_true
    end

    it "handles C# 11 raw string literals with a quote fence" do
      src = "var r = \"\"\" a } \" \"\" }\"\" b \"\"\"; tail();"
      lex = Noir::CSharpLexer.new(src)
      lex.in_code?(src.index!("tail")).should be_true
      lex.masked_lines[0].count('}').should eq(0)
    end

    it "blanks a char literal so a brace char is not counted" do
      Noir::CSharpLexer.new("c = '}'; d = '\\''; e();").masked_lines[0].count('}').should eq(0)
    end
  end

  describe "#matching_delimiter" do
    it "closes a method block past a `}` inside a string" do
      src = "{ var j = T(\"a } b\"); More(); }"
      lex = Noir::CSharpLexer.new(src)
      lex.matching_delimiter(src.index!('{')).should eq(src.size - 1)
    end

    it "does not let `/*/` self-close a block comment" do
      src = "/*/ Route(\"x\") */ ok();"
      lex = Noir::CSharpLexer.new(src)
      lex.in_code?(src.index!("Route")).should be_false
      lex.in_code?(src.index!("ok")).should be_true
    end
  end

  describe "#masked_lines" do
    it "matches String#lines element count and per-line length (incl. CRLF)" do
      {"a\nb\n", "x\r\ny()\r\n", "p => Q(\"x;y\");\nN();", "only"}.each do |src|
        raw = src.lines
        ml = Noir::CSharpLexer.new(src).masked_lines
        ml.size.should eq(raw.size)
        raw.each_with_index { |l, i| ml[i].size.should eq(l.size) }
      end
    end
  end

  describe "#statement_end" do
    it "ignores a `;` inside a string literal" do
      src = "var x = T(\"a;b\"); next();"
      lex = Noir::CSharpLexer.new(src)
      src[0...lex.statement_end(0)].should eq("var x = T(\"a;b\");")
    end
  end

  describe "#tokens" do
    it "produces a structural stream with idents, punctuation and string spans" do
      src = "app.MapGet(\"/x\", H);"
      kinds = Noir::CSharpLexer.new(src).tokens.map(&.kind)
      kinds.should eq([
        :ident, :dot, :ident, :lparen, :string, :comma, :ident, :rparen, :semicolon,
      ])
    end
  end
end
