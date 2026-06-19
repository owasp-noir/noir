require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Roda < RubyEngine
    HTTP_METHOD_MATCHERS = ["get", "post", "put", "delete", "patch", "head", "options"]

    # Precompile the per-verb routing-tree regexes once at load time.
    # Crystal recompiles an interpolated regex literal on every match, so
    # the `r.<verb>` matchers used to rebuild 21 regexes for every line of
    # every route block. `_BLOCK` = `r.get "x" do |..|`/`{`, `_STRING` =
    # `r.get "path"`, `_BARE` = `r.get` (do/brace/slash/eol).
    RODA_VERB_BLOCK = HTTP_METHOD_MATCHERS.to_h do |verb|
      {verb, /\br\.#{verb}\s+(.+?)\s*(?:do\b\s*(?:\|([^|]*)\|)?|\{\s*(?:\|([^|]*)\|)?)/}
    end
    RODA_VERB_STRING = HTTP_METHOD_MATCHERS.to_h do |verb|
      {verb, /\br\.#{verb}\s+['"]([^'"]+)['"]/}
    end
    RODA_VERB_BARE = HTTP_METHOD_MATCHERS.to_h do |verb|
      {verb, /\br\.#{verb}\b\s*(?:do\b|\{|\/|$)/}
    end

    alias PrefixEntry = NamedTuple(depth: Int32, segments: Array(String), path_params: Array(String))

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      parallel_file_scan do |path|
        next unless path.ends_with?(".rb")
        next if ruby_non_production_path?(path)
        analyze_file(path, include_callee)
      end

      @result
    end

    private def analyze_file(path : String, include_callee : Bool)
      content = read_file_content(path)
      return unless content.includes?("Roda") || content.includes?("route do")

      lines = content.lines
      in_route = false
      depth = 0
      prefix_stack = [] of PrefixEntry
      last_endpoint_index = -1

      lines.each_with_index do |line, index|
        next unless line.valid_encoding?

        stripped_for_code = strip_comment(line)

        unless in_route
          if stripped_for_code =~ /\broute\s+(?:do\b|\{)/
            in_route = true
            depth = count_opens(stripped_for_code) - count_closes(stripped_for_code)
            prefix_stack.clear
            last_endpoint_index = -1
          end
          next
        end

        emitted = process_route_line(stripped_for_code, path, index, depth, prefix_stack, lines, include_callee)
        if emitted >= 0
          last_endpoint_index = emitted
        end

        extract_params_for_line(stripped_for_code, last_endpoint_index)

        opens = count_opens(stripped_for_code)
        closes = count_closes(stripped_for_code)
        depth += opens - closes

        while !prefix_stack.empty? && prefix_stack.last[:depth] > depth
          prefix_stack.pop
        end

        if depth <= 0
          in_route = false
          depth = 0
          prefix_stack.clear
          last_endpoint_index = -1
        end
      end
    end

    private def process_route_line(line : String, path : String, index : Int32,
                                   depth : Int32,
                                   prefix_stack : Array(PrefixEntry),
                                   lines : Array(String),
                                   include_callee : Bool) : Int32
      if m = line.match(/\br\.(?:on|is)\s+(.+?)\s*(?:do\b\s*(?:\|([^|]*)\|)?|\{\s*(?:\|([^|]*)\|)?)/)
        segments, path_params = parse_on_args(m[1], m[2]? || m[3]?)
        unless segments.empty? && path_params.empty?
          prefix_stack << {depth: depth + 1, segments: segments, path_params: path_params}
        end
        return -1
      end

      if line =~ /\br\.root\b/
        url = build_url(collect_segments(prefix_stack), nil, nil)
        url = "/" if url.empty?
        ep = build_endpoint(url, "GET", path, index)
        apply_path_params(ep, prefix_stack)
        attach_route_callees(ep, lines, index, path) if include_callee
        @result << ep
        return @result.size - 1
      end

      # Every routing matcher below requires the `r.` request receiver, so
      # skip the whole verb sweep for lines that cannot contain one.
      return -1 unless line.includes?("r.")

      HTTP_METHOD_MATCHERS.each do |verb|
        if m = line.match(RODA_VERB_BLOCK[verb])
          segments, path_params = parse_on_args(m[1], m[2]? || m[3]?)
          unless segments.empty? && path_params.empty?
            url = build_url(collect_segments(prefix_stack), nil, segments)
            ep = build_endpoint(url, verb.upcase, path, index)
            apply_path_params(ep, prefix_stack)
            path_params.each { |name| ep.push_param(Param.new(name, "", "path")) }
            attach_route_callees(ep, lines, index, path) if include_callee
            @result << ep
            return @result.size - 1
          end
        end

        if m = line.match(RODA_VERB_STRING[verb])
          url = build_url(collect_segments(prefix_stack), m[1], nil)
          ep = build_endpoint(url, verb.upcase, path, index)
          apply_path_params(ep, prefix_stack)
          attach_route_callees(ep, lines, index, path) if include_callee
          @result << ep
          return @result.size - 1
        end

        if line =~ RODA_VERB_BARE[verb]
          url = build_url(collect_segments(prefix_stack), nil, nil)
          url = "/" if url.empty?
          ep = build_endpoint(url, verb.upcase, path, index)
          apply_path_params(ep, prefix_stack)
          attach_route_callees(ep, lines, index, path) if include_callee
          @result << ep
          return @result.size - 1
        end
      end

      -1
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      if block = extract_route_block(lines, index)
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
    end

    private def extract_route_block(lines : Array(String), index : Int32) : Tuple(String, Int32)?
      return if index >= lines.size

      start_line = Noir::RubyCalleeExtractor.strip_comment(lines[index], preserve_strings: true).strip
      return extract_ruby_do_block(lines, index) if start_line.match(/\bdo\b/)
      extract_ruby_brace_block(lines, index) if start_line.includes?('{')
    end

    private def extract_ruby_brace_block(lines : Array(String), start_index : Int32) : Tuple(String, Int32)?
      return if start_index >= lines.size

      start_line = Noir::RubyCalleeExtractor.strip_comment(lines[start_index], preserve_strings: true)
      open_index = start_line.index('{')
      return unless open_index

      body_lines = [] of String
      body_start_line = start_index + 2
      depth = 1
      tail = start_line[(open_index + 1)..].strip
      tail = tail.sub(/^\|[^|]*\|\s*/, "")

      unless tail.empty?
        body, depth = consume_brace_block_fragment(tail, depth)
        unless body.empty?
          body_start_line = start_index + 1
          body_lines << body
        end
        return {body_lines.join("\n"), body_start_line} if depth == 0
      end

      index = start_index + 1
      while index < lines.size
        body, depth = consume_brace_block_fragment(Noir::RubyCalleeExtractor.strip_comment(lines[index], preserve_strings: true), depth)
        if depth == 0
          body_lines << body unless body.empty?
          break
        end

        body_lines << lines[index]
        index += 1
      end

      {body_lines.join("\n"), body_start_line}
    end

    private def consume_brace_block_fragment(fragment : String, depth : Int32) : Tuple(String, Int32)
      current_depth = depth
      in_string = false
      escaped = false
      quote = '\0'

      body = String.build do |io|
        fragment.each_char do |char|
          if in_string
            io << char
            if escaped
              escaped = false
            elsif char == '\\'
              escaped = true
            elsif char == quote
              in_string = false
            end
          elsif char == '"' || char == '\''
            in_string = true
            quote = char
            io << char
          elsif char == '{'
            current_depth += 1
            io << char
          elsif char == '}'
            current_depth -= 1
            break if current_depth == 0

            io << char
          else
            io << char
          end
        end
      end

      {body.strip, current_depth}
    end

    private def extract_params_for_line(line : String, last_endpoint_index : Int32)
      return unless last_endpoint_index >= 0 && last_endpoint_index < @result.size

      endpoint = @result[last_endpoint_index]

      line.scan(/r\.params\[['"]([\w\-]+)['"]\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/r\.params\[:([\w]+)\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/(?<!r\.)\bparams\[['"]([\w\-]+)['"]\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/(?<!r\.)\bparams\[:([\w]+)\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "query")) if m.size > 1
      end
      line.scan(/r\.cookies\[['"]([\w\-]+)['"]\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "cookie")) if m.size > 1
      end
      line.scan(/r\.cookies\[:([\w]+)\]/) do |m|
        endpoint.push_param(Param.new(m[1], "", "cookie")) if m.size > 1
      end
      line.scan(/request\.env\[['"]HTTP_([\w]+)['"]\]/) do |m|
        if m.size > 1
          header = m[1].split('_').map(&.capitalize).join('-')
          endpoint.push_param(Param.new(header, "", "header"))
        end
      end
    end

    private def collect_segments(stack : Array(PrefixEntry)) : Array(String)
      segs = [] of String
      stack.each { |entry| segs.concat(entry[:segments]) }
      segs
    end

    private def apply_path_params(endpoint : Endpoint, stack : Array(PrefixEntry))
      stack.each do |entry|
        entry[:path_params].each do |name|
          endpoint.push_param(Param.new(name, "", "path"))
        end
      end
    end

    private def build_url(prefix : Array(String), single : String?, extras : Array(String)?) : String
      parts = [] of String
      prefix.each { |s| append_segments(parts, s) }
      append_segments(parts, single) if single
      extras.try &.each { |s| append_segments(parts, s) }
      parts.empty? ? "/" : "/" + parts.join("/")
    end

    private def append_segments(parts : Array(String), raw : String)
      raw.split("/").each do |piece|
        trimmed = piece.strip
        parts << trimmed unless trimmed.empty?
      end
    end

    private def parse_on_args(args : String, block_args : String? = nil) : Tuple(Array(String), Array(String))
      segments = [] of String
      path_params = [] of String
      matcher_arg_names = block_args ? block_args.split(",").map(&.strip).reject(&.empty?) : [] of String
      matcher_index = 0

      args.split(",").each do |part|
        token = part.strip
        next if token.empty?
        if token.starts_with?(':')
          name = token[1..].gsub(/[^\w]/, "")
          unless name.empty?
            segments << "{#{name}}"
            path_params << name
          end
          matcher_index += 1
        elsif token.matches?(/\A(?:Integer|String|Float|Hash|Array|[A-Z]\w*)\z/)
          if name = matcher_arg_names[matcher_index]?
            clean_name = name.gsub(/[^\w]/, "")
            unless clean_name.empty?
              segments << "{#{clean_name}}"
              path_params << clean_name
            end
          end
          matcher_index += 1
        elsif m = token.match(/['"]([^'"]+)['"]/)
          segments << m[1]
        end
      end
      {segments, path_params}
    end

    private def strip_comment(line : String) : String
      Noir::RubyCalleeExtractor.strip_comment(line, preserve_strings: true)
    end

    private def count_opens(line : String) : Int32
      opens = line.scan(/\bdo\b|\{/).size
      opens += 1 if line.match(/(?:^|=[^=>])\s*(if|unless|case|begin|while|until|for|class|module|def)\b/)
      opens
    end

    private def count_closes(line : String) : Int32
      line.scan(/\bend\b|\}/).size
    end

    private def build_endpoint(url : String, method : String, path : String, index : Int32) : Endpoint
      Endpoint.new(url, method, Details.new(PathInfo.new(path, index + 1)))
    end
  end
end
