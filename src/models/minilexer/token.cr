class Token
  property type : Symbol
  property value : String
  property index : Int32
  property position : Int32
  property line : Int32  

  def initialize(@type, @value, @index, @position, @line)
  end

  def is?(type)
    @type == type
  end

  def to_s
    if @value == "\n"
      @value = "\\n"
    elsif @value == "\t"
      @value = "\\t"
    end
    "#{@type} '#{@value}'"
  end
end
