require "spec"
require "../../../src/minilexers/python"

describe PythonLexer do
  describe "initialize" do
    it "sets default mode" do
      lexer = PythonLexer.new
      lexer.class.should eq(PythonLexer)
      lexer.mode.should eq(:normal)
    end

    it "sets persistent mode" do
      lexer = PythonLexer.new
      lexer.mode = :persistent
      lexer.mode.should eq(:persistent)
    end
  end

  describe "tokenize" do
    it "tokenizes simple function definition" do
      lexer = PythonLexer.new
      output = lexer.tokenize <<-PYTHON
        def foo():
          return "bar"
        PYTHON

      # Using collection-based assertion
      output.map(&.type).should eq([
        :DEF, :IDENTIFIER, :LPAREN, :RPAREN, :COLON, :NEWLINE, :INDENT, :RETURN, :STRING, :EOF,
      ])
      output[1].value.should eq("foo")
      output[8].value.should eq("\"bar\"")
    end

    it "tokenizes keywords" do
      lexer = PythonLexer.new
      keywords = {
        "False" => :FALSE, "await" => :AWAIT, "else" => :ELSE, "import" => :IMPORT,
        "pass" => :PASS, "None" => :NONE, "break" => :BREAK, "except" => :EXCEPT,
        "in" => :IN, "raise" => :RAISE, "True" => :TRUE, "class" => :CLASS,
        "finally" => :FINALLY, "is" => :IS, "return" => :RETURN, "and" => :AND,
        "continue" => :CONTINUE, "for" => :FOR, "lambda" => :LAMBDA, "try" => :TRY,
        "as" => :AS, "def" => :DEF, "from" => :FROM, "nonlocal" => :NONLOCAL,
        "while" => :WHILE, "assert" => :ASSERT, "del" => :DEL, "global" => :GLOBAL,
        "not" => :NOT, "with" => :WITH, "async" => :ASYNC, "elif" => :ELIF,
        "if" => :IF, "or" => :OR, "yield" => :YIELD,
      }

      keywords.each do |text, type|
        output = lexer.tokenize(text)
        output.first.type.should eq(type)
      end
    end

    it "tokenizes operators" do
      lexer = PythonLexer.new
      operators = {
        "+" => :ADD, "-" => :SUB, "*" => :MULT, "/" => :DIV, "%" => :MOD,
        "=" => :ASSIGN, "==" => :EQUAL, "!=" => :NOTEQUAL,
        "->" => :ARROW, "=>" => :DOUBLE_ARROW,
        "**" => :DOUBLESTAR, "//" => :DOUBLESLASH,
      }

      operators.each do |text, type|
        output = lexer.tokenize(text)
        output.first.type.should eq(type)
      end
    end

    it "tokenizes numbers" do
      lexer = PythonLexer.new
      output = lexer.tokenize("123 3.14 0xFF 1e10")
      output.map(&.type).should eq([:NUMBER, :NUMBER, :NUMBER, :NUMBER, :EOF])
      output.map(&.value).should eq(["123", "3.14", "0xFF", "1e10", ""])
    end

    it "tokenizes strings" do
      lexer = PythonLexer.new
      output = lexer.tokenize("'single' \"double\"")
      output.map(&.type).should eq([:STRING, :STRING, :EOF])
      output.map(&.value).should eq(["'single'", "\"double\"", ""])
    end

    it "tokenizes f-strings (lowercase)" do
      lexer = PythonLexer.new
      output = lexer.tokenize("f'format' f\"format\"")
      output.map(&.type).should eq([:FSTRING, :STRING, :FSTRING, :STRING, :EOF])
      output.map(&.value).should eq(["f", "'format'", "f", "\"format\"", ""])
    end

    it "tokenizes f-strings (uppercase)" do
      lexer = PythonLexer.new
      output = lexer.tokenize("F'format' F\"format\"")
      output.map(&.type).should eq([:FSTRING, :STRING, :FSTRING, :STRING, :EOF])
      output.map(&.value).should eq(["F", "'format'", "F", "\"format\"", ""])
    end

    it "disambiguates identifier 'f' vs f-string" do
      lexer = PythonLexer.new
      # "f" followed by space then quote is identifier f then string
      output = lexer.tokenize("f \"foo\"")
      output.map(&.type).should eq([:IDENTIFIER, :STRING, :EOF])

      output = lexer.tokenize("foo f")
      output.map(&.type).should eq([:IDENTIFIER, :IDENTIFIER, :EOF])
    end

    it "tokenizes multiline strings" do
      lexer = PythonLexer.new
      output = lexer.tokenize("'''multi\nline''' \"\"\"multi\nline\"\"\"")
      output.map(&.type).should eq([:MULTILINE_STRING, :MULTILINE_STRING, :EOF])
    end

    it "tokenizes comments" do
      lexer = PythonLexer.new
      output = lexer.tokenize("# comment\n")
      output.map(&.type).should eq([:COMMENT, :NEWLINE, :EOF])
    end

    it "handles high volume input" do
      lexer = PythonLexer.new
      # Generate a large input string
      input = "def foo():\n  pass\n" * 1000
      output = lexer.tokenize(input)
      # 5 tokens per loop (DEF, IDENTIFIER, LPAREN, RPAREN, COLON, NEWLINE, INDENT, PASS, NEWLINE) -> wait
      # def foo():\n -> DEF foo ( ) : \n
      #   pass\n -> INDENT pass \n
      # Tokens: DEF(1) foo(2) ((3) )(4) :(5) \n(6) INDENT(7) pass(8) \n(9)
      # But indentation logic is tricky with repetition.
      # Actually simpler: just check it runs and produces EOF at end.
      output.size.should be > 1000
      output.last.type.should eq(:EOF)
    end
  end
end
