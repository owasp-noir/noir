require "../../../models/analyzer"
require "../../../miniparsers/clojure_callee_extractor"
require "../../../utils/utils"

module Analyzer::Clojure
  class Compojure < Analyzer
    ROUTE_METHODS = {
      "GET"     => "GET",
      "POST"    => "POST",
      "PUT"     => "PUT",
      "DELETE"  => "DELETE",
      "PATCH"   => "PATCH",
      "HEAD"    => "HEAD",
      "OPTIONS" => "OPTIONS",
      "ANY"     => "ANY",
    }
    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      all_files.each do |path|
        next unless clojure_file?(path)

        content = read_file_content(path)
        next unless compojure_source?(content)

        scan_forms(content, 0, content.bytesize, "", path, include_callee)
      end

      Fiber.yield
      @result
    end

    private def clojure_file?(path : String) : Bool
      CLOJURE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
    end

    private def compojure_source?(content : String) : Bool
      content.includes?("compojure.core") || content.includes?("defroutes") || content.includes?("(context")
    end

    private def scan_forms(source : String, start_index : Int32, end_index : Int32, prefix : String, path : String, include_callee : Bool)
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
          when "context"
            context_path, _ = first_string_literal(source, after_symbol, form_end)
            next_prefix = context_path ? join_path(prefix, context_path) : prefix
            scan_forms(source, after_symbol, form_end, next_prefix, path, include_callee)
          when "defroutes", "routes"
            scan_forms(source, after_symbol, form_end, prefix, path, include_callee)
          else
            if route_method = ROUTE_METHODS[base]?
              add_route(source, i, after_symbol, form_end, prefix, path, route_method, include_callee)
            else
              scan_forms(source, after_symbol, form_end, prefix, path, include_callee)
            end
          end

          i = form_end + 1
        else
          i += 1
        end
      end
    end

    private def add_route(source : String, form_start : Int32, args_start : Int32, form_end : Int32,
                          prefix : String, path : String, method : String, include_callee : Bool)
      route_path, path_end = first_string_literal(source, args_start, form_end)
      return unless route_path

      full_path = join_path(prefix, route_path)
      endpoint = Endpoint.new(full_path, method, Details.new(PathInfo.new(path, line_number_for(source, form_start))))

      path_param_names = extract_path_param_names(route_path)
      path_param_names.each do |name|
        endpoint.push_param(Param.new(name, "", "path"))
      end

      if binding = extract_binding(source, path_end + 1, form_end)
        extract_query_param_names(binding, path_param_names).each do |name|
          endpoint.push_param(Param.new(name, "", "query"))
        end
      end

      attach_route_callees(endpoint, source, path_end + 1, form_end, path) if include_callee

      @result << endpoint
    end

    private def attach_route_callees(endpoint : Endpoint, source : String, args_start : Int32, form_end : Int32, path : String)
      body_start = route_body_start(source, args_start, form_end)
      return if body_start >= form_end

      body = source.byte_slice(body_start, form_end - body_start)
      start_line = line_number_for(source, body_start)
      callees = Noir::ClojureCalleeExtractor.callees_for_body(body, path, start_line)
      Noir::ClojureCalleeExtractor.attach_to(endpoint, callees)
    end

    private def route_body_start(source : String, index : Int32, limit : Int32) : Int32
      i = skip_ws_and_comments(source, index, limit)
      return i if i >= limit

      case source.byte_at(i).unsafe_chr
      when '['
        binding_end = find_matching_delimiter(source, i, '[', ']', limit)
        binding_end > i ? binding_end + 1 : i
      when '{'
        binding_end = find_matching_delimiter(source, i, '{', '}', limit)
        binding_end > i ? binding_end + 1 : i
      when '('
        i
      else
        _, after_symbol = read_symbol(source, i, limit)
        after_symbol
      end
    end

    private def extract_path_param_names(route_path : String) : Array(String)
      names = [] of String
      route_path.scan(/:([A-Za-z_][\w\-]*)/) do |match|
        names << match[1]
      end
      names
    end

    private def extract_query_param_names(binding : String, path_param_names : Array(String)) : Array(String)
      # `{:keys [...]}` style request-map destructuring — extract keys directly.
      return extract_keys_from_map(binding, path_param_names) if binding.starts_with?('{')
      return [] of String if !binding.starts_with?('[')

      names = [] of String
      path_param_set = path_param_names.to_set
      inner = binding[1...binding.size - 1]

      # `:as`/`:or` followed by a `{...}` block bind/default the whole
      # request map — keys inside are existing symbols, not query params.
      # Strip those maps before any further harvesting.
      inner_clean = inner.gsub(/:(?:as|or)\s*\{[^{}]*\}/, " ")

      # Vector binding may carry inline destructuring sub-maps like
      # `[foo {:keys [bar]}]`. Capture inline `:keys`/`:strs`/`:syms`
      # before stripping the embedded maps from token scanning.
      embedded_keys = extract_destructured_keys(inner_clean)

      # Strip embedded `{...}` blocks so we don't catch token names
      # *inside* destructuring shapes via the loose word scanner.
      inner_no_maps = inner_clean.gsub(/\{[^{}]*\}/, " ")

      skip_next = false
      inner_no_maps.scan(/:?[A-Za-z_][\w\-!?*]*/) do |match|
        token = match[0]

        # `:as` / `:or` bind the whole request map / supply defaults —
        # the following symbol is not a query param.
        if token == ":as" || token == ":or"
          skip_next = true
          next
        end

        # Skip Clojure-style keywords (`:foo`) entirely.
        next if token.starts_with?(':')

        if skip_next
          skip_next = false
          next
        end

        next if path_param_set.includes?(token)
        next if names.includes?(token)
        names << token
      end

      # Drop `&` rest-bindings: the symbol immediately after `&` collects
      # remaining args, not a query param. Detect by scanning the cleaned
      # inner so the `:as`/`:or` strip doesn't interfere.
      rest_match = inner_clean.match(/&\s+([A-Za-z_][\w\-!?*]*)/)
      if rest_match
        names.delete(rest_match[1])
      end

      embedded_keys.each do |key|
        next if path_param_set.includes?(key)
        next if names.includes?(key)
        names << key
      end

      names
    end

    private def extract_keys_from_map(binding : String, path_param_names : Array(String)) : Array(String)
      names = [] of String
      path_param_set = path_param_names.to_set
      extract_destructured_keys(binding).each do |key|
        next if path_param_set.includes?(key)
        next if names.includes?(key)
        names << key
      end
      names
    end

    private def extract_destructured_keys(text : String) : Array(String)
      keys = [] of String
      # Match plain `:keys`/`:strs`/`:syms` and namespace-qualified forms
      # like `:my.ns/keys` (the value half drops the namespace at bind time).
      text.scan(/:(?:[A-Za-z_][\w\-.]*\/)?(?:keys|strs|syms)\s+\[([^\]]+)\]/) do |match|
        match[1].scan(/[A-Za-z_][\w\-!?*]*/) do |inner|
          keys << inner[0]
        end
      end
      keys
    end

    private def extract_binding(source : String, index : Int32, limit : Int32) : String?
      i = skip_ws_and_comments(source, index, limit)
      return if i >= limit

      case source.byte_at(i).unsafe_chr
      when '['
        binding_end = find_matching_delimiter(source, i, '[', ']', limit)
        binding_end > i ? source.byte_slice(i, binding_end - i + 1) : nil
      when '{'
        binding_end = find_matching_delimiter(source, i, '{', '}', limit)
        binding_end > i ? source.byte_slice(i, binding_end - i + 1) : nil
      when '('
        nil
      else
        token, _ = read_symbol(source, i, limit)
        token.empty? ? nil : token
      end
    end

    private def first_string_literal(source : String, index : Int32, limit : Int32) : Tuple(String?, Int32)
      i = skip_ws_and_comments(source, index, limit)
      while i < limit
        case source.byte_at(i).unsafe_chr
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          literal_end = skip_string(source, i, limit)
          return {decode_string_literal(source.byte_slice(i, literal_end - i + 1)), literal_end}
        when '(', '[', '{'
          break
        else
          i += 1
        end
      end

      {nil, i}
    end

    private def decode_string_literal(raw : String) : String
      return raw unless raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2

      inner = raw[1...raw.size - 1]
      inner.gsub(/\\(.)/, "\\1")
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
