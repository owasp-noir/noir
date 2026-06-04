require "../../spec_helper"
require "../../../src/minilexers/scala_lexer"

describe Noir::ScalaLexer do
  it "keeps both masked views aligned with the source length" do
    src = "val s = \"a\"\nval t = \"\"\"x\ny\"\"\"\n/* a /* b */ c */ z()"
    lex = Noir::ScalaLexer.new(src)
    lex.masked.size.should eq(src.size)
    lex.code.size.should eq(src.size)
  end

  describe "two masked views" do
    it "keeps regular strings in the code view but blanks them structurally" do
      src = "path(\"users\")"
      lex = Noir::ScalaLexer.new(src)
      lex.code_lines[0].should eq("path(\"users\")") # routes are string args
      lex.masked_lines[0].should eq("path(       )") # blanked for brace matching
    end

    it "blanks triple-quoted bodies in BOTH views (threaded across lines)" do
      src = "val d =\n  \"\"\"\n  path(\"ghost\")\n  \"\"\"\npath(\"real\")"
      lex = Noir::ScalaLexer.new(src)
      code = lex.code_lines.join("\n")
      code.includes?("ghost").should be_false # inside the triple-quote
      code.includes?("path(\"real\")").should be_true
    end

    it "blanks nested block comments across lines" do
      src = "/* a /* b\n   path(\"ghost\") */ c */\npath(\"real\")"
      lex = Noir::ScalaLexer.new(src)
      lex.in_code?(src.index!("ghost")).should be_false      # inside the comment
      lex.in_code?(src.index!("path(\"real")).should be_true # the real route's `path`
    end

    it "blanks a char literal but leaves a `'symbol` as code" do
      lex = Noir::ScalaLexer.new("val c = '}'; val s = 'sym")
      lex.masked_lines[0].count('}').should eq(0) # char literal masked
      lex.in_code?("val c = '}'; val s = 'sym".index!("sym")).should be_true
    end
  end

  describe "#matching_delimiter" do
    it "closes a brace block past a `}` inside a string" do
      src = "{ val j = T(\"a } b\"); more() }"
      lex = Noir::ScalaLexer.new(src)
      lex.matching_delimiter(src.index!('{')).should eq(src.size - 1)
    end
  end

  describe "#masked_lines / #code_lines" do
    it "match String#lines element count and per-line length (incl. CRLF)" do
      {"a\nb\n", "x\r\ny\r\n", "p(\"q\")\nr()", "only"}.each do |src|
        raw = src.lines
        lex = Noir::ScalaLexer.new(src)
        lex.masked_lines.size.should eq(raw.size)
        lex.code_lines.size.should eq(raw.size)
        raw.each_with_index do |l, i|
          lex.masked_lines[i].size.should eq(l.size)
          lex.code_lines[i].size.should eq(l.size)
        end
      end
    end
  end
end
