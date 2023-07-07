struct CodeBlock
  property depth : Int32
  property state : String

  def initialize
    @depth = 1
    @state = ""
  end

  def enter
    @depth += 1
  end

  def exit
    @depth -= 1
  end
end
