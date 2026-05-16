require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"

module Analyzer::Dart
  # Serverpod is an RPC-style backend framework. Server endpoints are
  # Dart classes that extend `Endpoint` (or `StreamingEndpoint`); each
  # public method takes a `Session` as its first parameter and is
  # exposed to clients as a callable RPC. The class name's `Endpoint`
  # suffix is dropped and the first character is lowercased to derive
  # the endpoint name (`OrderEndpoint` → `order`).
  #
  # Serverpod dispatches every call as a `POST` to `/<endpointName>`
  # with the method name and arguments encoded in the body. We surface
  # each method as `POST /<endpointName>/<methodName>` so individual
  # RPCs are visible in the output, with the non-`Session` arguments
  # reported as JSON body params.
  class Serverpod < Analyzer
    HTTP_METHOD         = "POST"
    RESERVED_DART_NAMES = %w[if else for while switch case return try catch finally throw new const final var late void await async assert]
    alias MethodParam = NamedTuple(name: String, type: String)

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".dart")

        content = read_file_content(path)
        process_file(path, content, include_callee)
      end

      @result
    end

    private def process_file(path : String, content : String, include_callee : Bool)
      cleaned = strip_dart_comments(content)

      cleaned.scan(/class\s+([A-Z][A-Za-z0-9_]*)(?:\s*<[^>]*>)?\s+extends\s+(?:StreamingEndpoint|Endpoint)\b/) do |match|
        class_name = match[1]
        match_end = match.end(0)
        match_start = match.begin(0)
        next unless match_end && match_start

        body_info = extract_braced_block(cleaned, match_end)
        next unless body_info

        body, body_start = body_info
        line_number = line_for_offset(content, match_start)
        endpoint_name = endpoint_name_for(class_name)
        process_class_body(path, endpoint_name, body, body_start, content, line_number, include_callee)
      end
    end

    private def endpoint_name_for(class_name : String) : String
      base = class_name
      base = base[0...(base.size - "Endpoint".size)] if base.ends_with?("Endpoint") && base.size > "Endpoint".size
      return class_name.downcase if base.empty?
      base[0].downcase.to_s + base[1..]
    end

    private def process_class_body(path : String,
                                   endpoint_name : String,
                                   body : String,
                                   body_start : Int32,
                                   file_content : String,
                                   fallback_line : Int32,
                                   include_callee : Bool)
      depth = 0
      in_string = false
      string_quote = '\0'
      i = 0

      while i < body.size
        c = body[i]

        if in_string
          if c == '\\' && i + 1 < body.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
          i += 1
          next
        when '{'
          depth += 1
          i += 1
          next
        when '}'
          depth -= 1 if depth > 0
          i += 1
          next
        else
          # fall through
        end

        if depth == 0 && c == '('
          rest = body[(i + 1)..]
          if rest.match(/\A\s*Session\s+[A-Za-z_][A-Za-z0-9_]*/)
            method_name = method_name_before(body, i)
            if method_name && !method_name.empty? && !method_name.starts_with?("_")
              close_paren = find_matching_paren(body, i)
              if close_paren
                params_text = body[(i + 1)...close_paren]
                params = parse_method_params(params_text)
                line = line_for_offset(file_content, body_start + i)
                line = fallback_line if line <= 0
                callees = include_callee ? callees_for_method_body(path, body, body_start, close_paren, file_content) : [] of Noir::DartCalleeExtractor::Entry
                emit_endpoint(path, endpoint_name, method_name, params, line, callees)
                i = close_paren + 1
                next
              end
            end
          end
        end

        i += 1
      end
    end

    private def method_name_before(body : String, paren_idx : Int32) : String?
      back = paren_idx - 1
      while back >= 0 && body[back].whitespace?
        back -= 1
      end
      name_end = back
      while back >= 0 && (body[back].alphanumeric? || body[back] == '_')
        back -= 1
      end
      name_start = back + 1
      return if name_start > name_end
      candidate = body[name_start..name_end]
      return if candidate.empty?
      return unless candidate[0].lowercase? || candidate[0] == '_'
      return if RESERVED_DART_NAMES.includes?(candidate)
      candidate
    end

    private def parse_method_params(params_text : String) : Array(MethodParam)
      result = [] of MethodParam
      stripped = params_text.gsub(/[\[\]{}]/, " ")
      split_top_level_commas(stripped).each do |raw|
        part = raw.strip
        next if part.empty?
        part = part.sub(/^required\s+/, "")
        part = part.split('=').first.strip
        last_space = last_top_level_space(part)
        next unless last_space
        type = part[0...last_space].strip
        name = part[(last_space + 1)..].strip
        next if name.empty? || type.empty?
        next if type == "Session"
        result << {name: name, type: type}
      end
      result
    end

    private def last_top_level_space(text : String) : Int32?
      depth = 0
      last = nil.as(Int32?)
      text.each_char_with_index do |c, i|
        case c
        when '<'
          depth += 1
        when '>'
          depth -= 1 if depth > 0
        when ' ', '\t', '\n'
          last = i if depth == 0
        else
          # ignore
        end
      end
      last
    end

    private def split_top_level_commas(text : String) : Array(String)
      parts = [] of String
      depth = 0
      start = 0
      i = 0
      while i < text.size
        c = text[i]
        case c
        when '<', '('
          depth += 1
        when '>', ')'
          depth -= 1 if depth > 0
        when ','
          if depth == 0
            parts << text[start...i]
            start = i + 1
          end
        else
          # ignore
        end
        i += 1
      end
      parts << text[start..]
      parts
    end

    private def emit_endpoint(path : String,
                              endpoint_name : String,
                              method_name : String,
                              params : Array(MethodParam),
                              line : Int32,
                              callees : Array(Noir::DartCalleeExtractor::Entry) = [] of Noir::DartCalleeExtractor::Entry)
      url = "/#{endpoint_name}/#{method_name}"
      details = Details.new(PathInfo.new(path, line))
      endpoint_params = params.map { |p| Param.new(p[:name], p[:type], "json") }
      endpoint = Endpoint.new(url, HTTP_METHOD, endpoint_params, details)
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      @result << endpoint
    end

    private def callees_for_method_body(path : String,
                                        class_body : String,
                                        class_body_start : Int32,
                                        close_paren : Int32,
                                        file_content : String) : Array(Noir::DartCalleeExtractor::Entry)
      body_info = Noir::DartCalleeExtractor.extract_body_after(class_body, close_paren + 1)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = line_for_offset(file_content, class_body_start + body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def find_matching_paren(text : String, open_idx : Int32) : Int32?
      depth = 0
      i = open_idx
      in_string = false
      string_quote = '\0'

      while i < text.size
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '('
          depth += 1
        when ')'
          depth -= 1
          return i if depth == 0
        else
          # ignore
        end
        i += 1
      end

      nil
    end

    private def extract_braced_block(text : String, start : Int32) : Tuple(String, Int32)?
      i = start
      while i < text.size && text[i] != '{'
        i += 1
      end
      return if i >= text.size

      body_start = i + 1
      depth = 1
      i += 1
      in_string = false
      string_quote = '\0'

      while i < text.size && depth > 0
        c = text[i]
        if in_string
          if c == '\\' && i + 1 < text.size
            i += 2
            next
          end
          in_string = false if c == string_quote
          i += 1
          next
        end

        case c
        when '"', '\''
          in_string = true
          string_quote = c
        when '{'
          depth += 1
        when '}'
          depth -= 1
          break if depth == 0
        else
          # ignore
        end
        i += 1
      end

      return if depth != 0
      {text[body_start...i], body_start}
    end

    private def strip_dart_comments(text : String) : String
      result = String::Builder.new
      i = 0
      chars = text.chars
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == string_quote
            in_string = false
          end
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        if i + 1 < chars.size && c == '/' && chars[i + 1] == '/'
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          if i < chars.size
            result << chars[i]
            i += 1
          end
          next
        end

        if i + 1 < chars.size && c == '/' && chars[i + 1] == '*'
          result << ' '
          result << ' '
          i += 2
          while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
            result << (chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
          if i + 1 < chars.size
            result << ' '
            result << ' '
            i += 2
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      i = 0
      while i < limit
        count += 1 if content[i] == '\n'
        i += 1
      end
      count
    end
  end
end
