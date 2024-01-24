class Token
  property type : Symbol
  property value : String
  property position : Int64

  def initialize(@type, @value, @position)
  end
end
