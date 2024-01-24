class MiniLexer
  property tokens : Array(Token)
  property mode : Symbol # :normal, :persistent

  def initialize
    @mode = :normal
  end

  def mode=(mode)
    @mode = mode
  end

  def tokenize(input : String) : Array(Token)
    results = tokenize_logic(input)

    if @mode == :persistent
      @tokens = @tokens + results
    end
  end

  def tokenize_logic(input : String) : Array(Token)
    # Add tokenize logic here
  end
end
