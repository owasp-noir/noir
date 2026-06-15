require "../../engines/javascript_engine"
require "../specification/graphql_sdl_parser"
require "../specification/graphql_typedefs"

module Analyzer::Javascript
  # GraphQL Yoga analyzer.
  #
  # Yoga (The Guild stack) embeds its schema as an SDL string inside
  # `createSchema({ typeDefs })`, and exposes the HTTP mount via the
  # `graphqlEndpoint` option of `createYoga(...)`. The host runtime
  # (Node http, Express, Hono, Bun, Cloudflare Workers, …) only affects
  # the base path; framework-specific analyzers already cover the
  # mounting side, so this analyzer focuses on the SDL → endpoint
  # translation and the `graphqlEndpoint` override.
  #
  # The Apollo analyzer's mechanism is reused almost verbatim — both
  # servers carry typeDefs as a backtick template literal — so the only
  # Yoga-specific work here is reading `graphqlEndpoint` for the mount.
  class GraphqlYoga < JavascriptEngine
    DEFAULT_GRAPHQL_PATH = "/graphql"

    # Cheap content hints used to gate the heavier SDL extraction.
    YOGA_HINTS = ["graphql-yoga", "createYoga"]

    def analyze
      parallel_file_scan do |path|
        begin
          content = read_file_content(path)
          next unless yoga_in_file?(content)
          process_file(path, content)
        rescue e
          @logger.debug "GraphQL Yoga analyzer: failed to process #{path}: #{e.message}"
        end
      end
      @result
    end

    private def yoga_in_file?(content : String) : Bool
      YOGA_HINTS.any? { |hint| content.includes?(hint) }
    end

    private def process_file(path : String, content : String)
      mount_path = detect_mount_path(content)
      Analyzer::Specification::GraphqlTypedefs.extract(content, skip_js_comments: true).each do |sdl, line_offset|
        endpoints = Analyzer::Specification::GraphqlSdlParser.parse(
          sdl, path,
          default_path: mount_path,
          tag_source: "js_graphql_yoga_analyzer",
          line_offset: line_offset,
        )
        endpoints.each { |ep| @result << ep }
      end
    end

    # `createYoga({ ..., graphqlEndpoint: '/api/graphql' })`. Falls back
    # to `/graphql` when omitted, matching Yoga's own default.
    private def detect_mount_path(content : String) : String
      if m = content.match(/['"]?graphqlEndpoint['"]?\s*:\s*['"]([^'"]+)['"]/)
        return m[1]
      end
      DEFAULT_GRAPHQL_PATH
    end
  end
end
