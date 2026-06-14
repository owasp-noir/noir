require "../../../models/analyzer"
require "../../../utils/utils"

module Analyzer::Clojure
  # Generic Ring handler analyzer — extracts endpoints from Clojure code that
  # dispatches directly on `(:uri request)` / `(:request-method request)` via
  # `case`, `condp`, or `cond`, without going through Compojure's routing macros.
  class Ring < Analyzer
    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}
    METHOD_KEYWORDS    = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      "any"     => "ANY",
    }

    def analyze
      all_files.each do |path|
        next unless clojure_file?(path)

        content = read_file_content(path)
        next unless ring_source?(content)

        seen = Set(String).new
        extract_vector_dispatches(content, path, seen)
        walk_forms(content, 0, content.bytesize, path, seen, nil)
      end

      Fiber.yield
      @result
    end

    private def clojure_file?(path : String) : Bool
      CLOJURE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
    end

    private def ring_source?(content : String) : Bool
      # Compojure files are handled by the Compojure analyzer; skipping them
      # avoids double extraction when both analyzers run on the same project.
      return false if content.includes?("compojure.core")
      return false if content.includes?("defroutes")
      content.includes?(":request-method") || content.includes?(":uri")
    end

    # `case`/`condp` clauses use literal vector keys like `[:get "/users"]`.
    private def extract_vector_dispatches(content : String, path : String, seen : Set(String))
      content.scan(/\[\s*:(get|post|put|delete|patch|head|options|any)\s+"((?:[^"\\]|\\.)*)"\s*\]/i) do |match|
        method = METHOD_KEYWORDS[match[1].downcase]
        route = decode_string(match[2])
        next unless route.starts_with?('/')
        # byte offset (line_number_for uses byte_slice; begin(0) is a char index)
        offset = match.byte_begin(0)
        emit_endpoint(content, path, offset, method, route, seen)
      end
    end

    # Walks Clojure forms looking for `(= "/path" (:uri ...))` comparisons.
    # When inside an `(and ...)` form, captures the sibling
    # `(= :method (:request-method ...))` so each branch carries its own
    # method instead of bleeding across `cond` clauses.
    private def walk_forms(source : String, start_index : Int32, end_index : Int32,
                           path : String, seen : Set(String), and_method : String?)
      i = start_index
      while i < end_index
        case source.byte_at(i).unsafe_chr
        when ';'
          i = skip_comment(source, i, end_index)
        when '"'
          i = skip_string(source, i, end_index) + 1
        when '('
          form_end = find_matching_delimiter(source, i, '(', ')', end_index)
          break if form_end <= i

          symbol_start = skip_ws_and_comments(source, i + 1, form_end)
          symbol, after_symbol = read_symbol(source, symbol_start, form_end)

          base = base_symbol(symbol)

          case base
          when "and"
            inner_method = scan_method_in(source, after_symbol, form_end)
            walk_forms(source, after_symbol, form_end, path, seen, inner_method)
          when "="
            if route = uri_equality_route(source, after_symbol, form_end)
              method = and_method || "GET"
              emit_endpoint(source, path, i, method, route, seen)
            else
              walk_forms(source, after_symbol, form_end, path, seen, and_method)
            end
          when "case", "condp"
            extract_uri_case_dispatch(source, base, after_symbol, form_end, path, seen)
            walk_forms(source, after_symbol, form_end, path, seen, and_method)
          else
            walk_forms(source, after_symbol, form_end, path, seen, and_method)
          end

          i = form_end + 1
        else
          i += 1
        end
      end
    end

    # `(case (:uri request) "/a" h1 "/b" h2 default)` and
    # `(condp = (:uri request) "/a" h1 "/b" h2 default)` dispatch directly on
    # the request URI with bare string keys. Only fires when the dispatch value
    # is a `(:uri ...)` accessor (and, for condp, the predicate is `=`), so a
    # `case` on any other value never produces phantom routes. Each clause key
    # in *key position* that is a `/`-rooted string literal — or a list of them
    # `("/a" "/b")` for fall-through — becomes a GET endpoint.
    private def extract_uri_case_dispatch(source : String, base : String, start : Int32, limit : Int32,
                                          path : String, seen : Set(String))
      i = skip_ws_and_comments(source, start, limit)

      if base == "condp"
        pred, after_pred = read_form_token(source, i, limit)
        return unless pred == "="
        i = after_pred
      end

      dispatch, after_dispatch = read_form_token(source, i, limit)
      return unless uri_accessor?(dispatch)

      emit_string_clause_keys(source, after_dispatch, limit, path, seen)
    end

    # Walk `key value key value … [default]` clauses, emitting an endpoint for
    # every key-position `/`-rooted string. Values (handler forms) are skipped
    # so a handler that happens to return a `/`-string is never a route.
    private def emit_string_clause_keys(source : String, start : Int32, limit : Int32,
                                        path : String, seen : Set(String))
      i = skip_ws_and_comments(source, start, limit)
      is_key = true
      while i < limit
        token, after = read_form_token(source, i, limit)
        break if token.empty?

        if is_key
          if token.starts_with?('"')
            route = decode_literal(token)
            emit_endpoint(source, path, i, "GET", route, seen) if route.starts_with?('/')
          elsif token.starts_with?('(')
            # Fall-through list of keys: `("/a" "/b")` — each string is a route.
            emit_list_string_keys(source, i + 1, find_matching_delimiter(source, i, '(', ')', limit), path, seen)
          end
        end

        is_key = !is_key
        i = after
      end
    end

    private def emit_list_string_keys(source : String, start : Int32, limit : Int32, path : String, seen : Set(String))
      i = skip_ws_and_comments(source, start, limit)
      while i < limit
        token, after = read_form_token(source, i, limit)
        break if token.empty?
        if token.starts_with?('"')
          route = decode_literal(token)
          emit_endpoint(source, path, i, "GET", route, seen) if route.starts_with?('/')
        end
        i = after
      end
    end

    # Within an `(= ...)` form, detect a comparison between a literal URI
    # string and a `(:uri ...)` request-map accessor (either order).
    private def uri_equality_route(source : String, start_index : Int32, end_index : Int32) : String?
      tokens = read_two_tokens(source, start_index, end_index)
      return unless tokens

      first, second = tokens
      if first.starts_with?('"') && uri_accessor?(second)
        decode_literal(first)
      elsif uri_accessor?(first) && second.starts_with?('"')
        decode_literal(second)
      end
    end

    # Within an `(and ...)` body, locate a sibling
    # `(= :method (:request-method ...))` comparison to attach as the branch
    # method. Only direct children of the `and` are inspected so nested
    # forms don't poison the lookup.
    private def scan_method_in(source : String, start_index : Int32, end_index : Int32) : String?
      i = skip_ws_and_comments(source, start_index, end_index)
      while i < end_index
        case source.byte_at(i).unsafe_chr
        when ';'
          i = skip_comment(source, i, end_index)
        when '"'
          i = skip_string(source, i, end_index) + 1
        when '('
          form_end = find_matching_delimiter(source, i, '(', ')', end_index)
          break if form_end <= i

          sym_start = skip_ws_and_comments(source, i + 1, form_end)
          symbol, after_symbol = read_symbol(source, sym_start, form_end)
          if base_symbol(symbol) == "="
            if method = method_equality(source, after_symbol, form_end)
              return method
            end
          end

          i = form_end + 1
        else
          i += 1
        end
        i = skip_ws_and_comments(source, i, end_index)
      end
      nil
    end

    private def method_equality(source : String, start_index : Int32, end_index : Int32) : String?
      tokens = read_two_tokens(source, start_index, end_index)
      return unless tokens

      first, second = tokens
      if (kw = method_keyword(first)) && request_method_accessor?(second)
        METHOD_KEYWORDS[kw]?
      elsif request_method_accessor?(first) && (kw = method_keyword(second))
        METHOD_KEYWORDS[kw]?
      end
    end

    private def method_keyword(token : String) : String?
      return unless token.starts_with?(':')
      lower = token[1..].downcase
      METHOD_KEYWORDS.has_key?(lower) ? lower : nil
    end

    private def uri_accessor?(token : String) : Bool
      token == "(:uri" || token.starts_with?("(:uri ") || token.starts_with?("(:uri\t") || token.starts_with?("(:uri\n")
    end

    private def request_method_accessor?(token : String) : Bool
      token == "(:request-method" || token.starts_with?("(:request-method ") || token.starts_with?("(:request-method\t") || token.starts_with?("(:request-method\n")
    end

    private def read_two_tokens(source : String, start_index : Int32, end_index : Int32) : Tuple(String, String)?
      first, after_first = read_form_token(source, start_index, end_index)
      return if first.empty?
      second, _ = read_form_token(source, after_first, end_index)
      return if second.empty?
      {first, second}
    end

    # Reads the next form-shaped token: a `(...)` form, a `"..."` string,
    # or a bare symbol/keyword. Returns the raw substring plus the index
    # immediately after it (whitespace skipped).
    private def read_form_token(source : String, start_index : Int32, end_index : Int32) : Tuple(String, Int32)
      i = skip_ws_and_comments(source, start_index, end_index)
      return {"", i} if i >= end_index

      char = source.byte_at(i).unsafe_chr
      case char
      when '('
        form_end = find_matching_delimiter(source, i, '(', ')', end_index)
        if form_end > i
          token = source.byte_slice(i, form_end - i + 1)
          {token, skip_ws_and_comments(source, form_end + 1, end_index)}
        else
          {"", i}
        end
      when '['
        form_end = find_matching_delimiter(source, i, '[', ']', end_index)
        if form_end > i
          token = source.byte_slice(i, form_end - i + 1)
          {token, skip_ws_and_comments(source, form_end + 1, end_index)}
        else
          {"", i}
        end
      when '{'
        form_end = find_matching_delimiter(source, i, '{', '}', end_index)
        if form_end > i
          token = source.byte_slice(i, form_end - i + 1)
          {token, skip_ws_and_comments(source, form_end + 1, end_index)}
        else
          {"", i}
        end
      when '"'
        str_end = skip_string(source, i, end_index)
        token = source.byte_slice(i, str_end - i + 1)
        {token, skip_ws_and_comments(source, str_end + 1, end_index)}
      else
        sym, after = read_symbol(source, i, end_index)
        {sym, skip_ws_and_comments(source, after, end_index)}
      end
    end

    private def decode_literal(raw : String) : String
      return raw unless raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
      inner = raw[1...raw.size - 1]
      inner.gsub(/\\(.)/, "\\1")
    end

    private def decode_string(raw : String) : String
      raw.gsub(/\\(.)/, "\\1")
    end

    private def emit_endpoint(content : String, path : String, offset : Int32, method : String, route : String, seen : Set(String))
      return unless route.starts_with?('/')
      key = "#{method} #{route}"
      return if seen.includes?(key)
      seen << key

      line = line_number_for(content, offset)
      endpoint = Endpoint.new(route, method, Details.new(PathInfo.new(path, line)))

      extract_path_param_names(route).each do |name|
        endpoint.push_param(Param.new(name, "", "path"))
      end

      @result << endpoint
    end

    private def extract_path_param_names(route : String) : Array(String)
      names = [] of String
      route.scan(/:([A-Za-z_][\w\-]*)/) do |match|
        names << match[1]
      end
      names
    end

    private def base_symbol(symbol : String) : String
      parts = symbol.split('/')
      parts.last? || symbol
    end

    private def read_symbol(source : String, index : Int32, limit : Int32) : Tuple(String, Int32)
      i = index
      while i < limit
        char = source.byte_at(i).unsafe_chr
        break if whitespace?(char) || {'(', ')', '[', ']', '{', '}', '"', ';'}.includes?(char)
        i += 1
      end
      {source.byte_slice(index, i - index), i}
    end

    private def skip_ws_and_comments(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit
        char = source.byte_at(i).unsafe_chr
        if whitespace?(char)
          i += 1
        elsif char == ';'
          i = skip_comment(source, i, limit)
        else
          break
        end
      end
      i
    end

    private def skip_comment(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit && source.byte_at(i).unsafe_chr != '\n'
        i += 1
      end
      i
    end

    private def skip_string(source : String, index : Int32, limit : Int32) : Int32
      i = index + 1
      escaping = false

      while i < limit
        char = source.byte_at(i).unsafe_chr
        if escaping
          escaping = false
        elsif char == '\\'
          escaping = true
        elsif char == '"'
          return i
        end
        i += 1
      end

      limit - 1
    end

    private def find_matching_delimiter(source : String, index : Int32, open_char : Char, close_char : Char, limit : Int32) : Int32
      depth = 0
      i = index

      while i < limit
        char = source.byte_at(i).unsafe_chr
        case char
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          i = skip_string(source, i, limit)
        when open_char
          depth += 1
        when close_char
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end

      index
    end

    private def line_number_for(source : String, index : Int32) : Int32
      source.byte_slice(0, index).count('\n') + 1
    end

    private def whitespace?(char : Char) : Bool
      char.whitespace?
    end
  end
end
