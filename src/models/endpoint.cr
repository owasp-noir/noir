struct Endpoint
  property url, method, params

  def initialize(@url : String, @method : String, @params = nil)
  end

  def initialize(@url : String, @method : String, @params : Array(Param))
  end
end

struct Param
  property name, value, param_type

  def initialize(@name : String, @value : String, @param_type : String)
  end
end
