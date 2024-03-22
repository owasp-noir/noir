require "json"
require "yaml"

struct Tag
  include JSON::Serializable
  include YAML::Serializable
  property name, description

  def initialize(@name : String, @description : String)
  end
end
