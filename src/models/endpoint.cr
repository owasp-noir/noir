require "json"
require "yaml"

struct Endpoint
  include JSON::Serializable
  include YAML::Serializable
  property url, method, params, protocol

  def initialize(@url : String, @method : String)
    @params = [] of Param
    @protocol = "http"
  end

  def initialize(@url : String, @method : String, @params : Array(Param))
    @protocol = "http"
  end

  def set_protocol(protocol : String)
    @protocol = protocol
  end

  def push_param(param : Param)
    @params << param
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
  include YAML::Serializable
  property name, value, param_type

  # param_type can be "query", "json", "form", "header", "cookie"

  def initialize(@name : String, @value : String, @param_type : String)
  end
end

struct EndpointReference
  include JSON::Serializable
  property endpoint, metadata

  def initialize(@endpoint : Endpoint, @metadata : Hash(Symbol, String))
  end
end
