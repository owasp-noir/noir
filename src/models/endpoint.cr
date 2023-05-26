require "json"

struct Endpoint
  include JSON::Serializable
  property url, method, params

  def initialize(@url : String, @method : String)
    @params = [] of Param
  end

  def initialize(@url : String, @method : String, @params : Array(Param))
  end
end

struct Param
  include JSON::Serializable
  property name, value, param_type

  def initialize(@name : String, @value : String, @param_type : String)
  end
end
