require "json"

struct Endpoint
  include JSON::Serializable
  property url, method, params

  def initialize(@url : String, @method : String)
    @params = [] of Param
  end

  def initialize(@url : String, @method : String, @params : Array(Param))
  end

  def params_to_hash
    params_hash = {} of String => Hash(String, String)
    params_hash["query"] = {} of String => String
    params_hash["json"] = {} of String => String
    params_hash["form"] = {} of String => String

    @params.each do |param|
      params_hash[param.param_type][param.name] = param.value
    end

    params_hash
  end
end

struct Param
  include JSON::Serializable
  property name, value, param_type

  def initialize(@name : String, @value : String, @param_type : String)
  end
end
