require "../../engines/javascript_engine"
require "../specification/graphql_sdl_parser"

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
      extract_typedefs(content).each do |sdl, line_offset|
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

    # Returns pairs of (SDL string, line_offset) for every `typeDefs`
    # template literal in `content`. `line_offset` is the 0-based line
    # number in the source file where the SDL begins, so the downstream
    # parser's relative line numbers can be shifted back to absolute
    # positions.
    #
    # `typeDefs:` and `typeDefs =` both match — covering object-property
    # form (`createSchema({ typeDefs: \`...\` })`) and standalone const
    # declaration (`const typeDefs = \`...\``). The const form is what
    # makes the ES2015 `{ typeDefs }` shorthand "just work": the SDL is
    # already harvested at the const declaration, so the shorthand
    # reference doesn't need separate handling.
    private def extract_typedefs(content : String) : Array(Tuple(String, Int32))
      results = [] of Tuple(String, Int32)
      pattern = /\btypeDefs\s*[:=]\s*/

      content.scan(pattern) do |m|
        pos = (m.begin(0) || 0) + m[0].size
        pos = skip_tag(content, pos)
        pos = skip_js_comments(content, pos)

        next if pos >= content.size
        case content[pos]
        when '['
          collect_in_brackets(content, pos, results)
        when '`'
          collect_single(content, pos, results)
        end
      end

      results
    end

    # Yoga's docs idiomatically write `typeDefs: /* GraphQL */ \`...\``
    # so editors can syntax-highlight the SDL. Skip JS line/block
    # comments before reading the value.
    private def skip_js_comments(content : String, pos : Int32) : Int32
      while pos < content.size
        ch = content[pos]
        if ch.ascii_whitespace?
          pos += 1
          next
        end
        if ch == '/' && pos + 1 < content.size
          nxt = content[pos + 1]
          if nxt == '/'
            pos += 2
            while pos < content.size && content[pos] != '\n'
              pos += 1
            end
            next
          elsif nxt == '*'
            pos += 2
            while pos + 1 < content.size && !(content[pos] == '*' && content[pos + 1] == '/')
              pos += 1
            end
            pos += 2 if pos + 1 < content.size
            next
          end
        end
        break
      end
      pos
    end

    private def skip_tag(content : String, pos : Int32) : Int32
      return pos if pos >= content.size
      if tag = content.match(/\G(gql|graphql)\s*/, pos)
        return pos + tag[0].size
      end
      pos
    end

    private def collect_in_brackets(content : String, open_pos : Int32, results : Array(Tuple(String, Int32)))
      depth = 1
      pos = open_pos + 1
      while pos < content.size && depth > 0
        ch = content[pos]
        case ch
        when '['
          depth += 1
          pos += 1
        when ']'
          depth -= 1
          pos += 1
        when '`'
          if extracted = extract_template_literal(content, pos)
            sdl, next_pos = extracted
            line_offset = line_at(content, pos) - 1
            results << {sdl, line_offset}
            pos = next_pos
          else
            pos += 1
          end
        else
          pos += 1
        end
      end
    end

    private def collect_single(content : String, backtick_pos : Int32, results : Array(Tuple(String, Int32)))
      return unless extracted = extract_template_literal(content, backtick_pos)
      sdl, _ = extracted
      line_offset = line_at(content, backtick_pos) - 1
      results << {sdl, line_offset}
    end

    private def extract_template_literal(content : String, start_pos : Int32) : Tuple(String, Int32)?
      return if start_pos >= content.size || content[start_pos] != '`'
      end_pos = find_closing_backtick(content, start_pos + 1)
      return if end_pos.nil?

      raw = content[(start_pos + 1)...end_pos]
      {strip_interpolations(raw), end_pos + 1}
    end

    private def find_closing_backtick(content : String, start : Int32) : Int32?
      pos = start
      while pos < content.size
        ch = content[pos]
        case ch
        when '`'
          return pos
        when '\\'
          pos += 2
        when '$'
          if pos + 1 < content.size && content[pos + 1] == '{'
            depth = 1
            pos += 2
            while pos < content.size && depth > 0
              c2 = content[pos]
              case c2
              when '{' then depth += 1
              when '}' then depth -= 1
              end
              pos += 1
            end
          else
            pos += 1
          end
        else
          pos += 1
        end
      end
      nil
    end

    private def strip_interpolations(s : String) : String
      String.build(s.size) do |io|
        pos = 0
        while pos < s.size
          ch = s[pos]
          if ch == '\\' && pos + 1 < s.size
            io << ' '
            io << (s[pos + 1] == '\n' ? '\n' : ' ')
            pos += 2
          elsif ch == '$' && pos + 1 < s.size && s[pos + 1] == '{'
            depth = 1
            pos += 2
            io << "  "
            while pos < s.size && depth > 0
              c2 = s[pos]
              case c2
              when '{' then depth += 1
              when '}' then depth -= 1
              end
              if depth == 0
                io << ' '
                pos += 1
                break
              end
              io << (c2 == '\n' ? '\n' : ' ')
              pos += 1
            end
          else
            io << ch
            pos += 1
          end
        end
      end
    end

    private def line_at(content : String, pos : Int32) : Int32
      return 1 if pos <= 0
      content[0, pos].count('\n') + 1
    end
  end
end
