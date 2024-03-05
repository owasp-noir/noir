require "../models/minilexer/*"

class GolangLexer < MiniLexer
  @in_double_quote = false
  @in_single_quote = false
  @buffer = ""
  @identifier = :code

  def initialize
    super
  end

  def tokenize_logic(input : String) : Array(Token)
    results = [] of Token

    input.each_char_with_index do |char, index|
      case char.bytes[0]
      when 34 # double quote
        if @in_double_quote
          results << Token.new(:string, @buffer, index)
          @in_double_quote = false
          @identifier = :code
          @buffer = ""
        else
          results << Token.new(@identifier, @buffer, index)
          @in_double_quote = true
          @identifier = :string
        end       
      when 10 # newline
        if @buffer != ""
          results << Token.new(@identifier, @buffer, index)
        end
        results << Token.new(:newline, "\n", index)
        @buffer = ""
        @identifier = :code
      else
        @buffer += char
      end

      if index == input.size - 1
        results << Token.new(@identifier, @buffer, index)
      end
    end

    results
  end
end
