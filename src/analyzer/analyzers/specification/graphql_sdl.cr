require "../../engines/specification_engine"
require "./graphql_sdl_parser"

module Analyzer::Specification
  # Parses GraphQL SDL schema documents (`*.graphql`, `*.gql`, `*.graphqls`)
  # and emits one endpoint per Query / Mutation / Subscription field.
  #
  # Operation documents (`query Foo { ... }`) are intentionally not handled
  # here — the runtime file_analyzers/graphql_analyzer covers that surface.
  #
  # The SDL grammar itself lives in `GraphqlSdlParser` so other analyzers
  # (Apollo Server inline typeDefs, GraphQL Yoga, etc.) can share it.
  class GraphqlSdl < SpecificationEngine
    analyzer_for "graphql_sdl"

    def analyze
      each_spec_file(Noir::LocatorKeys::GRAPHQL_SDL) do |sdl_file|
        content = read_file_content(sdl_file)
        GraphqlSdlParser.parse(content, sdl_file).each { |ep| @result << ep }
      end

      @result
    end
  end
end
