struct CodeBlock
  property depth : Integer

  def initialize
    @depth = 1
  end

  def enter
    @depth += 1
  end

  def exit
    @depth -= 1
  end
end
