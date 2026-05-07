require "../../../models/analyzer"
require "set"

module Analyzer::Haskell
  class Servant < Analyzer
    HTTP_METHOD_VERBS = %w[GET POST PUT DELETE PATCH OPTIONS HEAD]

    alias TypeAlias = NamedTuple(body: String, source: String, line: Int32)

    def analyze
      type_aliases = {} of String => TypeAlias

      all_files.each do |path|
        next if File.directory?(path)
        next unless haskell_source?(path)

        content = read_file_content(path)
        extract_type_aliases(content).each do |entry|
          type_aliases[entry[:name]] = {
            body:   entry[:body],
            source: path,
            line:   entry[:line],
          }
        end
      end

      reference_counts = Hash(String, Int32).new(0)
      type_aliases.each do |_, entry|
        referenced_aliases(entry[:body], type_aliases.keys).each do |name|
          reference_counts[name] += 1
        end
      end

      type_aliases.each do |name, entry|
        next if reference_counts[name] > 0

        expanded = expand_references(entry[:body], type_aliases)
        next unless contains_servant_signature?(expanded)

        process_api_body(entry[:source], entry[:line], expanded)
      end

      @result
    end

    private def haskell_source?(path : String) : Bool
      path.ends_with?(".hs") || path.ends_with?(".lhs")
    end

    private def extract_type_aliases(content : String) : Array(NamedTuple(name: String, body: String, line: Int32))
      results = [] of NamedTuple(name: String, body: String, line: Int32)
      cleaned = strip_haskell_comments(content)
      lines = cleaned.lines

      i = 0
      while i < lines.size
        line = lines[i]
        match = line.match(/^type\s+([A-Z][A-Za-z0-9_']*)(?:\s+[a-z][A-Za-z0-9_']*)*\s*=\s*(.*)$/)
        if match
          name = match[1]
          first_body = match[2]
          start_line = i + 1
          body_parts = [first_body]
          j = i + 1
          while j < lines.size
            next_line = lines[j]
            stripped = next_line.lstrip
            if stripped.empty?
              break
            elsif starts_with_whitespace?(next_line) || stripped.starts_with?(":<|>") || stripped.starts_with?(":>")
              body_parts << next_line
              j += 1
            else
              break
            end
          end
          body = body_parts.join("\n").strip
          results << {name: name, body: body, line: start_line}
          i = j
        else
          i += 1
        end
      end

      results
    end

    private def starts_with_whitespace?(line : String) : Bool
      first = line[0]?
      return false unless first
      first == ' ' || first == '\t'
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
          i += 2
          while i < chars.size && brace_depth > 0
            if i + 1 < chars.size && chars[i] == '-' && chars[i + 1] == '}'
              brace_depth -= 1
              i += 2
            elsif i + 1 < chars.size && chars[i] == '{' && chars[i + 1] == '-'
              brace_depth += 1
              i += 2
            else
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

    private def referenced_aliases(body : String, known_names : Array(String)) : Array(String)
      found = Set(String).new
      body.scan(/\b([A-Z][A-Za-z0-9_']*)\b/) do |match|
        next if match.size < 2
        name = match[1]
        found << name if known_names.includes?(name)
      end
      found.to_a
    end

    private def expand_references(body : String, type_aliases : Hash(String, TypeAlias)) : String
      do_expand(body, type_aliases, Set(String).new)
    end

    private def do_expand(body : String, type_aliases : Hash(String, TypeAlias), visited : Set(String)) : String
      body.gsub(/\b([A-Z][A-Za-z0-9_']*)\b/) do |raw, m|
        name = m[1]
        if type_aliases.has_key?(name) && !visited.includes?(name)
          new_visited = visited.dup
          new_visited << name
          "(#{do_expand(type_aliases[name][:body], type_aliases, new_visited)})"
        else
          raw
        end
      end
    end

    private def contains_servant_signature?(body : String) : Bool
      return true if body.includes?(":<|>")
      return true if body.includes?(":>") && body.match(/\b(Get|Post|Put|Delete|Patch|Options|Head|Verb)\b/)
      false
    end

    private def process_api_body(source : String, line_number : Int32, body : String)
      flat = flatten_alternatives(body)
      routes = split_top_level(flat, ":<|>")
      routes.each do |route|
        process_route(source, line_number, route)
      end
    end

    private def flatten_alternatives(body : String) : String
      current = body
      loop do
        routes = split_top_level(current, ":<|>")
        expanded = [] of String
        changed = false

        routes.each do |route|
          distributed = distribute_route(route)
          changed = true if distributed.size > 1
          expanded.concat(distributed)
        end

        next_body = expanded.join(" :<|> ")
        break next_body unless changed
        current = next_body
      end
    end

    private def distribute_route(route : String) : Array(String)
      segments = split_top_level(route, ":>")

      segments.each_with_index do |segment, idx|
        inner = unwrap_parens(segment.strip)
        next if inner == segment.strip
        sub_routes = split_top_level(inner, ":<|>")
        next if sub_routes.size <= 1

        results = [] of String
        sub_routes.each do |sub|
          new_segments = segments.dup
          new_segments[idx] = sub
          results << new_segments.join(" :> ")
        end
        return results
      end

      [route]
    end

    private def process_route(source : String, line_number : Int32, route : String)
      raw = unwrap_parens(route.strip)
      return if raw.empty?

      segments = split_top_level(raw, ":>")

      url_parts = [] of String
      params = [] of Param
      method = nil.as(String?)

      segments.each do |segment|
        seg = unwrap_parens(segment.strip)
        next if seg.empty?

        lit = match_string_literal(seg)
        if lit
          url_parts << lit
          next
        end

        head, args = split_head_args(seg)

        case head
        when "Capture", "Capture'"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          if name
            url_parts << ":#{name}"
            params << Param.new(name, type, "path")
          end
        when "CaptureAll"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          if name
            url_parts << "*#{name}"
            params << Param.new(name, type, "path")
          end
        when "QueryParam", "QueryParam'", "QueryParams"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          params << Param.new(name, type, "query") if name
        when "QueryFlag"
          name = extract_string_arg(args)
          params << Param.new(name, "Bool", "query") if name
        when "Header", "Header'"
          name = extract_string_arg(args)
          type = extract_type_arg(args)
          params << Param.new(name, type, "header") if name
        when "ReqBody", "ReqBody'", "StreamBody", "StreamBody'"
          type = extract_type_arg(args)
          params << Param.new("body", type, "body")
        else
          mapped = http_method_for(head)
          if mapped
            method = mapped
          elsif head == "Verb"
            verb = extract_verb_method(args)
            method = verb if verb
          end
        end
      end

      resolved_method = method
      return unless resolved_method

      url = url_parts.empty? ? "/" : "/#{url_parts.join("/")}"
      details = Details.new(PathInfo.new(source, line_number))
      endpoint_params = params.map { |p| Param.new(p.name, p.value, p.param_type) }
      @result << Endpoint.new(url, resolved_method, endpoint_params, details)
    end

    private def http_method_for(token : String) : String?
      case token
      when "Get", "GetNoContent"
        "GET"
      when "Post", "PostNoContent", "PostCreated", "PostAccepted", "PostNonAuthoritative", "PostResetContent"
        "POST"
      when "Put", "PutNoContent", "PutCreated", "PutAccepted"
        "PUT"
      when "Delete", "DeleteNoContent", "DeleteAccepted"
        "DELETE"
      when "Patch", "PatchNoContent"
        "PATCH"
      when "Head"
        "HEAD"
      when "Options"
        "OPTIONS"
      end
    end

    private def extract_verb_method(args : String) : String?
      m = args.match(/'?\s*([A-Z]+)/)
      return unless m
      verb = m[1]
      verb if HTTP_METHOD_VERBS.includes?(verb)
    end

    private def match_string_literal(segment : String) : String?
      m = segment.match(/\A"((?:[^"\\]|\\.)*)"\z/)
      m ? m[1] : nil
    end

    private def split_head_args(segment : String) : Tuple(String, String)
      idx = 0
      while idx < segment.size && !segment[idx].whitespace?
        idx += 1
      end
      head = segment[0...idx]
      args = idx < segment.size ? segment[idx..].strip : ""
      {head, args}
    end

    private def extract_string_arg(args : String) : String?
      m = args.match(/"((?:[^"\\]|\\.)*)"/)
      m ? m[1] : nil
    end

    private def extract_type_arg(args : String) : String
      remaining = args
      m = args.match(/"(?:[^"\\]|\\.)*"\s*(.*)$/m)
      remaining = m[1] if m
      remaining = remaining.strip
      remaining = skip_promoted_lists(remaining)
      m = remaining.match(/\A([A-Za-z][A-Za-z0-9_']*)/)
      m ? m[1] : ""
    end

    private def skip_promoted_lists(input : String) : String
      remaining = input
      while remaining.starts_with?("'[")
        depth = 0
        idx = 0
        chars = remaining.chars
        while idx < chars.size
          c = chars[idx]
          if c == '['
            depth += 1
          elsif c == ']'
            depth -= 1
            if depth == 0
              idx += 1
              break
            end
          end
          idx += 1
        end
        remaining = idx < remaining.size ? remaining[idx..].strip : ""
      end
      remaining
    end

    private def unwrap_parens(text : String) : String
      stripped = text.strip
      while stripped.starts_with?("(") && stripped.ends_with?(")") && balanced_outermost?(stripped)
        stripped = stripped[1...-1].strip
      end
      stripped
    end

    private def balanced_outermost?(text : String) : Bool
      return false unless text.starts_with?("(") && text.ends_with?(")")
      depth = 0
      text.each_char_with_index do |c, i|
        if c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
          return false if depth == 0 && i < text.size - 1
        end
      end
      depth == 0
    end

    private def split_top_level(input : String, separator : String) : Array(String)
      parts = [] of String
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      start = 0
      i = 0
      sep_size = separator.size

      while i < input.size
        c = input[i]
        if c == '"'
          i += 1
          while i < input.size && input[i] != '"'
            i += 1 if input[i] == '\\' && i + 1 < input.size
            i += 1
          end
          i += 1 if i < input.size
          next
        end

        if c == '('
          paren_depth += 1
        elsif c == ')'
          paren_depth -= 1 if paren_depth > 0
        elsif c == '['
          bracket_depth += 1
        elsif c == ']'
          bracket_depth -= 1 if bracket_depth > 0
        elsif c == '{'
          brace_depth += 1
        elsif c == '}'
          brace_depth -= 1 if brace_depth > 0
        elsif paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 && matches_at?(input, i, separator)
          parts << input[start...i]
          i += sep_size
          start = i
          next
        end

        i += 1
      end

      parts << input[start..]
      parts.map(&.strip).reject(&.empty?)
    end

    private def matches_at?(input : String, index : Int32, sep : String) : Bool
      return false if index + sep.size > input.size
      sep.size.times do |k|
        return false if input[index + k] != sep[k]
      end
      true
    end
  end
end
