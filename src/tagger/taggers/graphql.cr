require "../../models/tagger"
require "../../models/endpoint"

class GraphqlTagger < Tagger
  WORDS = ["query", "mutation", "subscription", "operationname", "__schema", "__type", "graphql"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "graphql"
  end

  def perform(endpoints : Array(Endpoint))
    endpoints.each do |endpoint|
      tmp_params = [] of String

      endpoint.params.each do |param|
        tmp_params.push param.name.to_s.downcase
      end

      # Check URL path for GraphQL indicators
      url_lower = endpoint.url.downcase
      is_graphql_url = url_lower.includes?("graphql") || url_lower.includes?("/gql")

      words_set = Set.new(WORDS)
      tmp_params_set = Set.new(tmp_params)
      intersection = words_set & tmp_params_set

      # Check that at least two parameters match or URL indicates GraphQL
      check = intersection.size.to_i >= 2 || is_graphql_url

      if check
        tag = Tag.new("graphql", "GraphQL endpoint for flexible API queries, potentially exposing schema introspection and nested data access.", "GraphQL")
        endpoint.add_tag(tag)
      end
    end
  end
end
