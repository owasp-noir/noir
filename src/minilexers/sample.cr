require "../models/minilexer/*"

class SampleLexer < Lexer
  def initialize
    super
    # Add custom initial state
  end

  def tokenize_logic
    # Add logic for each state
  end
end
