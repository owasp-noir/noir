class Token
  property type : Symbol
  property value : String
  property index : Int32
  property position : Int32
  property line : Int32

  def initialize(@type, @value, @index)
    @position = 0
    @line = 0
  end

  def initialize(@type, @value, @index, @position, @line)
  end

  def is?(type)
    @type == type
  end

  def to_s(io : IO) : Nil
    display = case @value
              when "\n" then "\\n"
              when "\t" then "\\t"
              else           @value
              end
    io << @type << " '" << display << "'"
  end
end
