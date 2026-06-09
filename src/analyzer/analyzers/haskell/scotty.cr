require "../../../models/analyzer"
require "../../../miniparsers/haskell_callee_extractor"
require "set"

module Analyzer::Haskell
  class Scotty < Analyzer
    HTTP_VERBS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "patch"   => "PATCH",
      "delete"  => "DELETE",
      "options" => "OPTIONS",
      "head"    => "HEAD",
    }

    ROUTE_LINE_REGEX    = /^([ \t]*)(?:[A-Z][A-Za-z0-9_']*\.)?(get|post|put|patch|delete|options|head)\s+"((?:[^"\\]|\\.)*)"(.*)$/
    ADDROUTE_LINE_REGEX = /^([ \t]*)(?:[A-Z][A-Za-z0-9_']*\.)?addroute\s+([A-Z]+)\s+"((?:[^"\\]|\\.)*)"(.*)$/

    QUERY_PARAM_REGEX = /(?<![A-Za-z0-9_'])(?:queryParam|queryParamMaybe|param|captureParam)\s+"((?:[^"\\]|\\.)*)"/
    FORM_PARAM_REGEX  = /(?<![A-Za-z0-9_'])(?:formParam|formParamMaybe|formParams)\s+"((?:[^"\\]|\\.)*)"/
    PATH_PARAM_REGEX  = /(?<![A-Za-z0-9_'])(?:pathParam|pathParamMaybe)\s+"((?:[^"\\]|\\.)*)"/
    HEADER_REGEX      = /(?<![A-Za-z0-9_'])header\s+"((?:[^"\\]|\\.)*)"/

    alias HandlerBody = Noir::HaskellCalleeExtractor::FunctionBody
    alias HandlerKey = Tuple(String, String)
    alias HandlerBodies = Hash(HandlerKey, Array(HandlerBody))

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      handler_bodies = include_callee ? build_handler_bodies : HandlerBodies.new

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        content = read_file_content(path)
        process_content(path, content, include_callee, handler_bodies)
      end

      @result
    end

    private def haskell_source?(path : String) : Bool
      path.ends_with?(".hs") || path.ends_with?(".lhs")
    end

    private def build_handler_bodies : HandlerBodies
      handlers = HandlerBodies.new

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        Noir::HaskellCalleeExtractor.function_bodies(read_file_content(path), path).each do |body|
          key = handler_key(configured_base_for(path), body[:name])
          handlers[key] ||= [] of HandlerBody
          handlers[key] << body
        end
      end

      handlers
    end

    private def handler_key(base_path : String, name : String) : HandlerKey
      {base_path, name}
    end

    private def process_content(source : String,
                                content : String,
                                include_callee : Bool,
                                handler_bodies : HandlerBodies)
      cleaned = strip_haskell_comments(content)
      lines = cleaned.lines
      idx = 0

      while idx < lines.size
        line = lines[idx]
        route = match_route(line)
        if route
          method = route[:method]
          path_template = route[:path]
          indent = route[:indent]
          body_start_line = idx + 1
          body_first_line_rest = route[:rest]

          body_end_idx = find_block_end(lines, idx, indent)
          body_text = collect_body(body_first_line_rest, lines, idx + 1, body_end_idx)

          url, path_params = build_url_and_params(path_template)
          handler_params = extract_handler_params(body_text, path_params)

          all_params = path_params + handler_params

          details = Details.new(PathInfo.new(source, body_start_line))
          endpoint = Endpoint.new(url, method, all_params, details)

          if include_callee
            attach_callees(endpoint, body_text, body_first_line_rest, source, body_start_line, handler_bodies)
          end

          @result << endpoint

          idx = body_end_idx + 1
        else
          idx += 1
        end
      end
    end

    private def match_route(line : String) : NamedTuple(indent: Int32, method: String, path: String, rest: String)?
      if m = line.match(ROUTE_LINE_REGEX)
        verb = m[2].downcase
        method = HTTP_VERBS[verb]?
        return unless method
        return {
          indent: m[1].size,
          method: method,
          path:   m[3],
          rest:   m[4],
        }
      end

      if m = line.match(ADDROUTE_LINE_REGEX)
        method = m[2].upcase
        return {
          indent: m[1].size,
          method: method,
          path:   m[3],
          rest:   m[4],
        }
      end

      nil
    end

    private def find_block_end(lines : Array(String), start_idx : Int32, indent : Int32) : Int32
      i = start_idx + 1
      while i < lines.size
        line = lines[i]
        stripped = line.strip
        unless stripped.empty?
          line_indent = leading_indent(line)
          break if line_indent <= indent
        end
        i += 1
      end
      i - 1
    end

    private def collect_body(first_rest : String, lines : Array(String), from : Int32, to_inclusive : Int32) : String
      parts = [] of String
      parts << first_rest
      i = from
      while i <= to_inclusive && i < lines.size
        parts << lines[i]
        i += 1
      end
      parts.join("\n")
    end

    private def leading_indent(line : String) : Int32
      count = 0
      line.each_char do |c|
        break unless c == ' ' || c == '\t'
        count += 1
      end
      count
    end

    private def build_url_and_params(path_template : String) : Tuple(String, Array(Param))
      params = [] of Param
      segments = path_template.split('/')
      rendered = [] of String

      segments.each do |segment|
        next if segment.empty?

        if segment.starts_with?(":")
          name = segment[1..]
          next if name.empty?
          rendered << ":#{name}"
          params << Param.new(name, "", "path")
        else
          rendered << segment
        end
      end

      url = rendered.empty? ? "/" : "/#{rendered.join("/")}"
      url = "/" + url unless url.starts_with?("/")
      {url, params}
    end

    private def extract_handler_params(body : String, path_params : Array(Param)) : Array(Param)
      params = [] of Param
      seen = Set(Tuple(String, String)).new
      path_names = path_params.map(&.name).to_set

      body.scan(PATH_PARAM_REGEX) do |m|
        name = m[1]
        next if name.empty?
        next if path_names.includes?(name)
        next unless seen.add?({name, "path"})
        params << Param.new(name, "", "path")
      end

      body.scan(QUERY_PARAM_REGEX) do |m|
        name = m[1]
        next if name.empty?
        next if path_names.includes?(name)
        next unless seen.add?({name, "query"})
        params << Param.new(name, "", "query")
      end

      body.scan(FORM_PARAM_REGEX) do |m|
        name = m[1]
        next if name.empty?
        next unless seen.add?({name, "body"})
        params << Param.new(name, "", "body")
      end

      body.scan(HEADER_REGEX) do |m|
        name = m[1]
        next if name.empty?
        next unless seen.add?({name, "header"})
        params << Param.new(name, "", "header")
      end

      if mentions_token?(body, "jsonData")
        params << Param.new("body", "JSON", "body") if seen.add?({"body", "body"})
      end

      if mentions_token?(body, "files")
        params << Param.new("files", "Multipart", "body") if seen.add?({"files", "body"})
      end

      params
    end

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The probed token set is fixed, so
    # precompile the matchers once at load time.
    TOKEN_PATTERNS = {
      "jsonData" => /(?<![A-Za-z0-9_'])jsonData(?![A-Za-z0-9_'])/,
      "files"    => /(?<![A-Za-z0-9_'])files(?![A-Za-z0-9_'])/,
    }

    private def mentions_token?(body : String, token : String) : Bool
      token_regex = TOKEN_PATTERNS[token]? || /(?<![A-Za-z0-9_'])#{Regex.escape(token)}(?![A-Za-z0-9_'])/
      !!body.match(token_regex)
    end

    private def attach_callees(endpoint : Endpoint,
                               body_text : String,
                               first_rest : String,
                               source : String,
                               body_start_line : Int32,
                               handler_bodies : HandlerBodies)
      callees = Noir::HaskellCalleeExtractor.callees_for_body(body_text, source, body_start_line)

      if named = inline_handler_name(first_rest)
        bodies = handler_bodies[handler_key(configured_base_for(source), named)]?
        if bodies && bodies.size == 1
          handler = bodies.first
          callees.concat(Noir::HaskellCalleeExtractor.callees_for_body(handler[:body], handler[:path], handler[:start_line]))
        end
      end

      Noir::HaskellCalleeExtractor.attach_to(endpoint, callees)
    end

    private def inline_handler_name(rest : String) : String?
      trimmed = rest.strip
      trimmed = trimmed[1..].strip if trimmed.starts_with?("$")
      return if trimmed.empty?
      return if trimmed.starts_with?("do")
      return if trimmed.starts_with?("(")

      m = trimmed.match(/\A([a-z_][A-Za-z0-9_']*)\s*$/)
      m ? m[1] : nil
    end

    private def strip_haskell_comments(text : String) : String
      result = String::Builder.new
      chars = text.chars
      i = 0
      brace_depth = 0
      in_string = false

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == '"'
            in_string = false
            result << c
            i += 1
            next
          else
            result << c
            i += 1
            next
          end
        end

        if brace_depth == 0 && c == '"'
          in_string = true
          result << c
          i += 1
          next
        end

        if i + 1 < chars.size && c == '{' && chars[i + 1] == '-'
          brace_depth += 1
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && brace_depth > 0
            if i + 1 < chars.size && chars[i] == '-' && chars[i + 1] == '}'
              brace_depth -= 1
              result << ' '
              result << ' '
              i += 2
            elsif i + 1 < chars.size && chars[i] == '{' && chars[i + 1] == '-'
              brace_depth += 1
              result << ' '
              result << ' '
              i += 2
            else
              result << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
          end
          next
        end

        if brace_depth == 0 && i + 1 < chars.size && c == '-' && chars[i + 1] == '-'
          while i < chars.size && chars[i] != '\n'
            i += 1
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end
  end
end
