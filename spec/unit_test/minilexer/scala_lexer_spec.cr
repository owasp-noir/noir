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

    it "keeps regular strings in the code view but blanks them structurally" do
      src = "path(\"users\")"
      lex = Noir::ScalaLexer.new(src)
      lex.code_lines[0].should eq("path(\"users\")") # routes are string args
      lex.masked_lines[0].should eq("path(       )") # blanked for brace matching
    end

    it "blanks a char literal but leaves a `'symbol` as code" do
      lex = Noir::ScalaLexer.new("val c = '}'; val s = 'sym")
      lex.masked_lines[0].count('}').should eq(0) # char literal masked
      lex.in_code?("val c = '}'; val s = 'sym".index!("sym")).should be_true
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

  describe "masked_lines / code_lines" do
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

  describe "string interpolation holes" do
    # There was no interpolation state at all: the first `"` inside `${…}`
    # closed the literal, so the hole's expression was lexed as code and the
    # next `"` re-opened a string. Nothing observable broke today (the Scala
    # analyzers key on braces, and in the simple case both stray parens
    # happened to land inside one of the two string spans), but the depth is
    # skewed the moment a paren falls on the wrong side of the split — so
    # these assert the lexer's own output rather than any endpoint count.
    it "keeps an interpolated string with a quoted hole as ONE string span" do
      src = "val x = s\"a ${cfg(\"k\")} b\""
      lex = Noir::ScalaLexer.new(src)

      lex.skip_ranges.should eq([src.index!('"')..src.size - 1])
      # `k` used to leak out of the string and be lexed as code.
      lex.in_code?(src.index!('k')).should be_false
    end

    it "keeps parenthesis depth balanced around an interpolated hole" do
      src = "foo(s\"${f(\"(\")}\")"
      lex = Noir::ScalaLexer.new(src)

      masked = lex.masked.join
      masked.count('(').should eq(1)
      masked.count(')').should eq(1)
    end

    it "does not treat `${` inside a plain (non-interpolated) string as a hole" do
      src = "val x = \"${cfg(\"k\")}\""
      lex = Noir::ScalaLexer.new(src)

      # No interpolator prefix, so `"${cfg("` really is the whole literal and
      # `k` really is code — same as before, and as Scala reads it.
      lex.in_code?(src.index!('k')).should be_true
    end

    it "treats `$$` as an escaped dollar rather than the start of a hole" do
      src = "val x = s\"$${literal} tail\""
      lex = Noir::ScalaLexer.new(src)

      lex.skip_ranges.size.should eq(1)
      lex.masked.should_not contain('{')
    end

    it "tracks holes in a triple-quoted interpolated string too" do
      src = "val x = s\"\"\"a ${f(\"\"\"b\"\"\")} c\"\"\"\npath(\"real\")"
      lex = Noir::ScalaLexer.new(src)

      lex.code_lines[0].includes?("b").should be_false # inside the triple quote
      lex.code_lines[1].should eq("path(\"real\")")
      lex.masked.join.count('(').should eq(1) # only `path(`
      lex.masked.join.count(')').should eq(1)
    end

    it "leaves the short `$ident` form as plain string content" do
      src = "val u = s\"/api/$version/users\""
      lex = Noir::ScalaLexer.new(src)

      lex.code_lines[0].should eq("val u = s\"/api/$version/users\"")
      lex.skip_ranges.should eq([src.index!('"')..src.size - 1])
    end
  end
end
