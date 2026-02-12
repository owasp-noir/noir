require "spec"
require "../../../src/minilexers/js_lexer"

describe Noir::JSLexer do
  describe "initialize" do
    it "initializes with source code" do
      lexer = Noir::JSLexer.new("var x = 1;")
      lexer.should be_a(Noir::JSLexer)
    end
  end

  describe "tokenize" do
    it "tokenizes basic punctuation" do
      lexer = Noir::JSLexer.new("(){}[],:;.")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([
        :lparen, :rparen, :lbrace, :rbrace, :lbracket, :rbracket,
        :comma, :colon, :semicolon, :dot
      ])
      tokens.map(&.value).should eq(["(", ")", "{", "}", "[", "]", ",", ":", ";", "."])
    end

    it "tokenizes operators" do
      lexer = Noir::JSLexer.new("+ =")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:plus, :assign])
      tokens.map(&.value).should eq(["+", "="])
    end

    it "tokenizes numbers" do
      lexer = Noir::JSLexer.new("123 45.67")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:number, :number])
      tokens.map(&.value).should eq(["123", "45.67"])
    end

    it "tokenizes strings" do
      lexer = Noir::JSLexer.new("'single' \"double\"")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:string, :string])
      tokens.map(&.value).should eq(["single", "double"])
    end

    it "tokenizes strings with escapes" do
      lexer = Noir::JSLexer.new("'sin\\'gle' \"dou\\\"ble\"")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:string, :string])
      tokens.map(&.value).should eq(["sin'gle", "dou\"ble"])
    end

    it "tokenizes template literals" do
      lexer = Noir::JSLexer.new("`template`")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:template_literal])
      tokens.map(&.value).should eq(["template"])
    end

    it "tokenizes identifiers and keywords" do
      lexer = Noir::JSLexer.new("function const var let return if else for while")
      tokens = lexer.tokenize
      tokens.each do |token|
        token.type.should eq(:keyword)
      end
    end

    it "tokenizes literals" do
      lexer = Noir::JSLexer.new("true false null undefined")
      tokens = lexer.tokenize
      tokens.each do |token|
        token.type.should eq(:literal)
      end
    end

    it "tokenizes HTTP methods" do
      lexer = Noir::JSLexer.new("GET POST PUT DELETE OPTIONS HEAD PATCH")
      tokens = lexer.tokenize
      tokens.each do |token|
        token.type.should eq(:http_method)
      end
    end

    it "tokenizes standard identifiers" do
      lexer = Noir::JSLexer.new("myVar _private $special")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:identifier, :identifier, :identifier])
    end

    it "tokenizes single line comments" do
      lexer = Noir::JSLexer.new("// this is a comment\nvar x")
      tokens = lexer.tokenize
      # Comments are skipped in JSLexer, so we expect only "var x" tokens
      tokens.map(&.type).should eq([:keyword, :identifier])
      tokens.map(&.value).should eq(["var", "x"])
    end

    it "tokenizes multi-line comments" do
      lexer = Noir::JSLexer.new("/* comment */ var x")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:keyword, :identifier])
    end

    it "tokenizes regex literals" do
      lexer = Noir::JSLexer.new("return /abc/;")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:keyword, :regex, :semicolon])
      # Regex value includes flags after \x00
      tokens[1].value.should eq("abc\x00")
    end

    it "tokenizes regex with flags" do
      lexer = Noir::JSLexer.new("return /abc/gi;")
      tokens = lexer.tokenize
      tokens[1].type.should eq(:regex)
      tokens[1].value.should eq("abc\x00gi")
    end

    it "tokenizes regex with character classes" do
      lexer = Noir::JSLexer.new("return /[a-z]/;")
      tokens = lexer.tokenize
      tokens[1].type.should eq(:regex)
      tokens[1].value.should eq("[a-z]\x00")
    end

    it "distinguishes division from regex" do
      # 10 / 2
      lexer = Noir::JSLexer.new("10 / 2")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:number, :operator, :number])

      # x / y
      lexer = Noir::JSLexer.new("x / y")
      tokens = lexer.tokenize
      tokens.map(&.type).should eq([:identifier, :operator, :identifier])
    end

    it "identifies regex in complex contexts" do
      cases = {
        "( /abc/ )" => [:lparen, :regex, :rparen],
        "{ /abc/ }" => [:lbrace, :regex, :rbrace],
        "[ /abc/ ]" => [:lbracket, :regex, :rbracket],
        ", /abc/"   => [:comma, :regex],
        ": /abc/"   => [:colon, :regex],
        "= /abc/"   => [:assign, :regex],
        "case /abc/:" => [:keyword, :regex, :colon],
        "typeof /abc/" => [:keyword, :regex],
      }

      cases.each do |code, expected_types|
        lexer = Noir::JSLexer.new(code)
        tokens = lexer.tokenize
        tokens.map(&.type).should eq(expected_types)
      end
    end
  end
end
