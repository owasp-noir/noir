require "../models/minilexer/*"

class GolangLexer < MiniLexer
  def initialize
    super
    # You must proceed with the init of the MiniLexer class through super.

    # **********************
    # Add custom initial state
  end

  def tokenize_logic(input : String) : Array(Token)
    results = [] of Token

    # results << Token.new(:identifier, "foo", 3)
    results
  end
end
