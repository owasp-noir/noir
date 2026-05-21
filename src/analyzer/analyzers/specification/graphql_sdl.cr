require "../../../models/analyzer"
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
  class GraphqlSdl < Analyzer
    def analyze
      locator = CodeLocator.instance
      sdl_files = locator.all("graphql-sdl")
      return @result unless sdl_files.is_a?(Array(String))

      sdl_files.each do |sdl_file|
        next unless File.exists?(sdl_file)
        begin
          content = File.read(sdl_file, encoding: "utf-8", invalid: :skip)
          GraphqlSdlParser.parse(content, sdl_file).each { |ep| @result << ep }
        rescue e
          @logger.debug "GraphQL SDL: failed to parse #{sdl_file}"
          @logger.debug_sub e
        end
      end

      @result
    end
  end
end
