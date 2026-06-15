require "../../engines/javascript_engine"
require "../specification/graphql_sdl_parser"
require "../specification/graphql_typedefs"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Javascript
  # Apollo Server analyzer.
  #
  # Extracts endpoints from two surfaces:
  #   1. Inline `typeDefs` declarations carried in a backtick template literal
  #      (`typeDefs = gql\`...\`` or `typeDefs = \`#graphql ...\``), parsed
  #      via the shared GraphQL SDL parser.
  #   2. The mount path — either an Express `app.use('/path', expressMiddleware(...))`
  #      position or the standalone default of `/graphql`.
  #
  # Schema-first setups that load typeDefs from a separate `.graphql` file
  # (`import typeDefs from './schema.graphql'`) are handled by the
  # `graphql_sdl` analyzer, so no work is duplicated here.
  class Apollo < JavascriptEngine
    DEFAULT_GRAPHQL_PATH = "/graphql"

    # File-level signals that mark a JS/TS file as Apollo-relevant. The
    # parallel_file_scan walks every JS/TS source, so we gate with a cheap
    # substring check before doing the heavier SDL extraction.
    APOLLO_HINTS = ["@apollo/server", "apollo-server", "ApolloServer"]

    def analyze
      parallel_file_scan do |path|
        begin
          content = read_file_content(path)
          next unless apollo_in_file?(content)
          # A `gql\`type Query { ... }\`` schema inside a *.test/*.spec file
          # (or a mock/e2e tree) is a test fixture, not a deployed GraphQL
          # endpoint — skip it the same way the verb-DSL analyzers do.
          next if Noir::JSRouteExtractor.test_stub_only?(path, content)
          process_file(path, content)
        rescue e
          @logger.debug "Apollo analyzer: failed to process #{path}: #{e.message}"
        end
      end
      @result
    end

    private def apollo_in_file?(content : String) : Bool
      APOLLO_HINTS.any? { |hint| content.includes?(hint) }
    end

    private def process_file(path : String, content : String)
      mount_path = detect_mount_path(content)
      Analyzer::Specification::GraphqlTypedefs.extract(content).each do |sdl, line_offset|
        endpoints = Analyzer::Specification::GraphqlSdlParser.parse(
          sdl, path,
          default_path: mount_path,
          tag_source: "js_apollo_analyzer",
          line_offset: line_offset,
        )
        endpoints.each { |ep| @result << ep }
      end
    end

    # Look for an Express mount: `app.use('/graphql', expressMiddleware(server))`.
    # Falls back to `/graphql` when no explicit mount is found — that matches
    # the convention used by the SDL analyzer and most production deployments.
    private def detect_mount_path(content : String) : String
      if m = content.match(/\b(?:app|router|server|application)\s*\.\s*use\s*\(\s*['"]([^'"]+)['"]\s*,\s*(?:[A-Za-z_][\w]*\s*,\s*)?expressMiddleware\b/)
        return m[1]
      end
      DEFAULT_GRAPHQL_PATH
    end
  end
end
