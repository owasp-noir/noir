require "graphql/client"
require "graphql/client/http"

module GitHub
  HTTP = GraphQL::Client::HTTP.new("https://api.github.com/graphql")
  Schema = GraphQL::Client.load_schema(HTTP)
  Client = GraphQL::Client.new(schema: Schema, execute: HTTP)

  class QueryType
    def field(name)
      name
    end
  end
end
