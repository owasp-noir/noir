require "../models/minilexer/*"

class SampleLexer < MiniLexer
  def initialize
    super
    # You must proceed with the init of the MiniLexer class through super.

    # **********************
    # Add custom initial state
  end

  def tokenize_logic
    # Add logic for each state

    # **********************
    # e.g
    # results = [] of Token
    # your logic here
    # results << Token.new(:identifier, "foo", 3)
    # results
  end
end
