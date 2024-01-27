class Token
  property type : Symbol
  property value : String
  property position : Int64

  def initialize(@type, @value, @position)
  end

  def is?(type)
    @type == type
  end

  def to_s
    "#{@type} #{@value}"
  end
end
