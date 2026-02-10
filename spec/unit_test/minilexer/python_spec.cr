require "spec"
require "../../../src/minilexers/python"

describe PythonLexer do
  describe "initialize" do
    lexer = PythonLexer.new

    it "init" do
      lexer.class.should eq(PythonLexer)
    end

    it "default mode" do
      lexer.mode.should eq(:normal)
    end

    it "persistent mode" do
      lexer.mode = :persistent
      lexer.mode.should eq(:persistent)
    end
  end

  describe "tokenize" do
    lexer = PythonLexer.new

    it "simple function definition" do
      output = lexer.tokenize <<-PYTHON
        def foo():
          return "bar"
        PYTHON

      # Expected tokens:
      # DEF, IDENTIFIER(foo), LPAREN, RPAREN, COLON, NEWLINE, INDENT, RETURN, STRING("bar"), NEWLINE, INDENT (maybe?), EOF
      # Actually tokenize_logic loop:
      # 'd' -> match_other -> DEF
      # ' ' -> match_other -> skipped
      # 'f' -> match_other -> IDENTIFIER(foo)
      # '(' -> match_punctuation -> LPAREN
      # ')' -> match_punctuation -> RPAREN
      # ':' -> match_punctuation -> COLON
      # '\n' -> match_newline -> NEWLINE, match_indentation -> INDENT
      # 'r' -> match_other -> RETURN
      # ...

      # Let's see what we get.
      # Note: The heredoc indent is stripped by Crystal if using <<-PYTHON?
      # Yes, it strips leading whitespace common to all lines.
      # But here the first line `def foo():` has 8 spaces indent in my code block.
      # The second line `  return "bar"` has 10 spaces.
      # So relative indent is 2 spaces.
      # Crystal heredoc `<<-` removes the indentation of the closing delimiter from each line.
      # `PYTHON` is indented by 8 spaces. So 8 spaces are removed.
      # `def foo():` (8 spaces) -> `def foo():` (0 spaces)
      # `  return "bar"` (10 spaces) -> `  return "bar"` (2 spaces)

      # So input string is:
      # def foo():\n  return "bar"\n

      idx = 0
      output[idx].type.should eq(:DEF); idx += 1
      output[idx].type.should eq(:IDENTIFIER); output[idx].value.should eq("foo"); idx += 1
      output[idx].type.should eq(:LPAREN); idx += 1
      output[idx].type.should eq(:RPAREN); idx += 1
      output[idx].type.should eq(:COLON); idx += 1
      output[idx].type.should eq(:NEWLINE); idx += 1
      output[idx].type.should eq(:INDENT); idx += 1
      output[idx].type.should eq(:RETURN); idx += 1
      output[idx].type.should eq(:STRING); output[idx].value.should eq("\"bar\""); idx += 1
      # output[idx].type.should eq(:NEWLINE); idx += 1
      output[idx].type.should eq(:EOF)
    end

    it "keywords" do
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
        output[0].type.should eq(type)
      end
    end

    it "operators" do
      # Test some operators
      operators = {
        "+" => :ADD, "-" => :SUB, "*" => :MULT, "/" => :DIV, "%" => :MOD,
        "=" => :ASSIGN, "==" => :EQUAL, "!=" => :NOTEQUAL,
        "->" => :ARROW, "=>" => :DOUBLE_ARROW, # "=>" is not python operator but in list?
        "**" => :DOUBLESTAR, "//" => :DOUBLESLASH,
      }

      operators.each do |text, type|
        output = lexer.tokenize(text)
        output[0].type.should eq(type)
      end
    end

    it "numbers" do
      output = lexer.tokenize("123 3.14 0xFF 1e10")
      output[0].type.should eq(:NUMBER); output[0].value.should eq("123")
      output[1].type.should eq(:NUMBER); output[1].value.should eq("3.14")
      output[2].type.should eq(:NUMBER); output[2].value.should eq("0xFF")
      output[3].type.should eq(:NUMBER); output[3].value.should eq("1e10")
    end

    it "strings" do
      output = lexer.tokenize("'single' \"double\" f'format' f\"format\"")
      output[0].type.should eq(:STRING); output[0].value.should eq("'single'")
      output[1].type.should eq(:STRING); output[1].value.should eq("\"double\"")
      output[2].type.should eq(:FSTRING)
      output[3].type.should eq(:STRING); output[3].value.should eq("'format'")
      output[4].type.should eq(:FSTRING)
      output[5].type.should eq(:STRING); output[5].value.should eq("\"format\"")
    end

    it "multiline strings" do
      output = lexer.tokenize("'''multi\nline''' \"\"\"multi\nline\"\"\"")
      output[0].type.should eq(:MULTILINE_STRING); output[0].value.should contain("multi\nline")
      output[1].type.should eq(:MULTILINE_STRING); output[1].value.should contain("multi\nline")
    end

    it "comments" do
      output = lexer.tokenize("# comment\n")
      output[0].type.should eq(:COMMENT); output[0].value.should eq("# comment")
      output[1].type.should eq(:NEWLINE)
    end

    it "indentation followed by keyword" do
      output = lexer.tokenize("\n  if")
      # \n -> NEWLINE
      # match_indentation -> "  " matches ^[\t ]+\b ?
      # "  " followed by "if" (word). Boundary exists.
      output[0].type.should eq(:NEWLINE)
      output[1].type.should eq(:INDENT)
      output[2].type.should eq(:IF)
    end
  end
end
