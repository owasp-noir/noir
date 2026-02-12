require "spec"
require "../../../src/minilexers/kotlin"

describe KotlinLexer do
  describe "initialize" do
    it "sets default mode" do
      lexer = KotlinLexer.new
      lexer.class.should eq(KotlinLexer)
      lexer.mode.should eq(:normal)
    end
  end

  describe "tokenize" do
    it "tokenizes basic function definition" do
      lexer = KotlinLexer.new
      output = lexer.tokenize <<-KOTLIN
        fun main() {
          println("Hello")
        }
        KOTLIN

      output.map(&.type).should eq([
        :FUN, :IDENTIFIER, :LPAREN, :RPAREN, :LCURL, :NEWLINE,
        :IDENTIFIER, :LPAREN, :STRING_LITERAL, :RPAREN, :NEWLINE,
        :RCURL,
      ])
      output[1].value.should eq("main")
      output[6].value.should eq("println")
      output[8].value.should eq("\"Hello\"")
    end

    it "tokenizes keywords" do
      lexer = KotlinLexer.new
      keywords = KotlinLexer::KEYWORDS
      keywords.each do |text, type|
        output = lexer.tokenize(text)
        output.first.type.should eq(type)
      end
    end

    it "tokenizes annotations" do
      lexer = KotlinLexer.new
      annotations = KotlinLexer::ANNOTATIONS
      annotations.each do |text, type|
        output = lexer.tokenize(text)
        output.first.type.should eq(type)
      end

      # Generic annotation
      output = lexer.tokenize("@Inject")
      output.first.type.should eq(:ANNOTATION)
      output.first.value.should eq("@Inject")
    end

    it "tokenizes punctuation" do
      lexer = KotlinLexer.new
      punctuation = KotlinLexer::PUNCTUATION
      punctuation.each do |char, type|
        output = lexer.tokenize(char.to_s)
        output.first.type.should eq(type)
      end
    end

    it "tokenizes operators" do
      lexer = KotlinLexer.new
      operators = KotlinLexer::OPERATORS
      operators.each do |op, type|
        output = lexer.tokenize(op.to_s)
        output.first.type.should eq(type)
      end
    end

    it "tokenizes numbers" do
      lexer = KotlinLexer.new
      # Integer
      output = lexer.tokenize("123")
      output.first.type.should eq(:INTEGER_LITERAL)

      # Float
      output = lexer.tokenize("3.14")
      output.first.type.should eq(:FLOAT_LITERAL)

      # Scientific notation
      output = lexer.tokenize("1.2e10")
      output.first.type.should eq(:FLOAT_LITERAL)

      # Underscore in number
      output = lexer.tokenize("1_000")
      output.first.type.should eq(:INTEGER_LITERAL)
    end

    it "tokenizes strings and chars" do
      lexer = KotlinLexer.new
      # Char
      output = lexer.tokenize("'a'")
      output.first.type.should eq(:CHAR_LITERAL)
      output.first.value.should eq("'a'")

      # String
      output = lexer.tokenize("\"hello\"")
      output.first.type.should eq(:STRING_LITERAL)
      output.first.value.should eq("\"hello\"")

      # Text block (triple quotes)
      output = lexer.tokenize("\"\"\"line1\nline2\"\"\"")
      output.first.type.should eq(:TEXT_BLOCK)
      output.first.value.should eq("\"\"\"line1\nline2\"\"\"")
    end

    it "tokenizes identifiers" do
      lexer = KotlinLexer.new
      output = lexer.tokenize("variableName _privateVar ClassName")
      output.map(&.type).should eq([:IDENTIFIER, :IDENTIFIER, :IDENTIFIER])
      output.map(&.value).should eq(["variableName", "_privateVar", "ClassName"])
    end

    it "tokenizes comments" do
      lexer = KotlinLexer.new
      # Single line comment
      output = lexer.tokenize("// comment\n")
      output.map(&.type).should eq([:NEWLINE]) # Comment is skipped

      # Multi line comment
      output = lexer.tokenize("/* multi\nline */")
      output.should be_empty # Comment is skipped
    end

    it "handles whitespace" do
      lexer = KotlinLexer.new
      output = lexer.tokenize("  \t\n")
      output.first.type.should eq(:NEWLINE)
      # Spaces and tabs are skipped
    end

    it "handles repeated calls correctly" do
      lexer = KotlinLexer.new

      output1 = lexer.tokenize("fun")
      output1.size.should eq(1)
      output1.first.type.should eq(:FUN)

      output2 = lexer.tokenize("val")
      output2.size.should eq(1)
      output2.first.type.should eq(:VAL)

      # This confirms that previous tokens are cleared
      output2.map(&.type).should_not contain(:FUN)
    end
  end
end
