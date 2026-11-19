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
      # A schema split across files is read as one per directory: grouping a
      # whole monorepo would cross-wire unrelated schemas.
      schemas = {} of String => Array(Tuple(String, String))
      each_spec_file(Noir::LocatorKeys::GRAPHQL_SDL) do |sdl_file|
        (schemas[File.dirname(sdl_file)] ||= [] of Tuple(String, String)) << {sdl_file, read_file_content(sdl_file)}
      end
      schemas.each_value { |sources| GraphqlSdlParser.parse_schema(sources).each { |ep| @result << ep } }

      @result
    end
  end
end
