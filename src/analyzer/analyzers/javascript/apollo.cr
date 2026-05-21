require "../../engines/javascript_engine"
require "../specification/graphql_sdl_parser"

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
      extract_typedefs(content).each do |sdl, line_offset|
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

    # Returns pairs of (SDL string, line_offset) for every `typeDefs`
    # template literal assignment in `content`. `line_offset` is the
    # 0-based line number in the source file where the SDL begins, so the
    # downstream parser's relative line numbers can be shifted back to
    # absolute positions.
    private def extract_typedefs(content : String) : Array(Tuple(String, Int32))
      results = [] of Tuple(String, Int32)
      pattern = /\btypeDefs\s*[:=]\s*/

      content.scan(pattern) do |m|
        pos = (m.begin(0) || 0) + m[0].size
        pos = skip_tag(content, pos)

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

    private def skip_tag(content : String, pos : Int32) : Int32
      return pos if pos >= content.size
      if tag = content.match(/\G(gql|graphql)\s*/, pos)
        return pos + tag[0].size
      end
      pos
    end

    # Pull every backtick-delimited string from inside a `[...]` block.
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

    # Extracts a template literal starting at `\``, returning the interior
    # text (with `${...}` interpolations and escapes replaced by spaces so
    # that line counts and offsets stay aligned) and the byte position
    # just past the closing backtick.
    private def extract_template_literal(content : String, start_pos : Int32) : Tuple(String, Int32)?
      return nil if start_pos >= content.size || content[start_pos] != '`'
      end_pos = find_closing_backtick(content, start_pos + 1)
      return nil if end_pos.nil?

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
