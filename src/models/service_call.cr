require "json"
require "yaml"

# References stay finite when services call each other. They identify a route
# within its project rather than embedding another endpoint recursively.
struct ServiceEndpoint
  include JSON::Serializable
  include YAML::Serializable
  getter project : String
  getter method : String
  getter url : String

  @[JSON::Field(ignore_serialize: variant.nil?)]
  @[YAML::Field(ignore_serialize: variant.nil?)]
  getter variant : String?

  def initialize(@project, @method, @url, @variant = nil)
  end
end

struct ServiceEdge
  include JSON::Serializable
  include YAML::Serializable
  getter endpoint : ServiceEndpoint
  getter matched_by : String
  getter path : String?
  getter line : Int32?

  def initialize(@endpoint, @matched_by, @path = nil, @line = nil)
  end
end

struct ServiceCall
  include JSON::Serializable
  include YAML::Serializable
  getter sink : AIContextEntry
  getter url : String?
  getter method : String?
  getter matches : Array(ServiceEdge)

  def initialize(@sink, @url = nil, @method = nil, @matches = [] of ServiceEdge)
  end
end
