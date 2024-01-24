class MiniLexer
  property tokens : Array(Token)
  property mode : Symbol # :normal, :persistent

  def initialize
    @mode = :normal
    @tokens = [] of Token
  end

  def mode=(mode)
    @mode = mode
  end

  def tokenize(input : String) : Array(Token)
    results = tokenize_logic(input)

    if @mode == :persistent
      @tokens = @tokens + results
    end

    results
  end

  def tokenize_logic(input : String) : Array(Token)
    # Add tokenize logic here
    results = [] of Token
    results << Token.new(:identifier, "foo", 3)

    results
  end

  def find(token_type : Symbol) : Array(Token)
    @tokens.select { |token| token.type == token_type }
  end
end
