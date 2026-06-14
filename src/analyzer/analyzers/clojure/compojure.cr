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
    # compojure.api.resource method keys (keyword form inside the resource map).
    RESOURCE_METHODS = {
      ":get"     => "GET",
      ":post"    => "POST",
      ":put"     => "PUT",
      ":delete"  => "DELETE",
      ":patch"   => "PATCH",
      ":head"    => "HEAD",
      ":options" => "OPTIONS",
      ":any"     => "ANY",
    }
    # compojure-api restructuring directives that name request params with a
    # `[name :- Schema ...]` binding vector in the route body.
    RESTRUCTURING_PARAMS = {
      ":query-params"  => "query",
      ":body-params"   => "json",
      ":path-params"   => "path",
      ":form-params"   => "form",
      ":header-params" => "header",
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
      content.includes?("compojure.core") ||
        content.includes?("compojure.api") ||
        content.includes?("defroutes") ||
        content.includes?("(context")
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
            context_path, _ = route_path_literal(source, after_symbol, form_end)
            context_path = normalize_route_path(context_path) if context_path
            next_prefix = context_path ? join_path(prefix, context_path) : prefix
            scan_forms(source, after_symbol, form_end, next_prefix, path, include_callee)
          when "defroutes", "routes"
            scan_forms(source, after_symbol, form_end, prefix, path, include_callee)
          when "resource"
            # compojure.api.resource: `(resource {:get {...} :post {...}})`
            # binds method handlers to the enclosing context path rather than
            # a route string. Falls back to plain recursion when the argument
            # is not a resource map (e.g. `(resource db Schema)`).
            unless add_resource(source, after_symbol, form_end, prefix, path, include_callee)
              scan_forms(source, after_symbol, form_end, prefix, path, include_callee)
            end
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
      raw_route_path, path_end = route_path_literal(source, args_start, form_end)
      return unless raw_route_path
      route_path = normalize_route_path(raw_route_path)

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

      # compojure-api routes declare typed params via `:query-params`/etc.
      # directives in the body rather than the binding vector.
      extract_restructuring_params(source, route_body_start(source, path_end + 1, form_end), form_end, endpoint)

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

    # Scan a route body for compojure-api restructuring directives
    # (`:query-params [x :- Long]`, `:body-params`, …) and lift their bound
    # names into endpoint params. Only top-level body forms are inspected, so
    # keywords nested inside the handler expression are never mistaken for
    # directives.
    private def extract_restructuring_params(source : String, body_start : Int32, form_end : Int32, endpoint : Endpoint)
      i = body_start
      while i < form_end
        i = skip_ws_and_comments(source, i, form_end)
        break if i >= form_end

        if source.byte_at(i).unsafe_chr == ':'
          keyword, after_kw = read_symbol(source, i, form_end)
          value_start = skip_ws_and_comments(source, after_kw, form_end)
          value_end = resource_end_of_value(source, value_start, form_end)

          if (ptype = RESTRUCTURING_PARAMS[keyword]?) &&
             value_start < value_end && source.byte_at(value_start).unsafe_chr == '['
            bind_end = find_matching_delimiter(source, value_start, '[', ']', value_end)
            if bind_end > value_start
              binding_param_names(source, value_start + 1, bind_end).each do |name|
                add_param_once(endpoint, name, ptype)
              end
            end
          end

          i = value_end
        else
          i = resource_end_of_value(source, i, form_end)
        end
      end
    end

    # Extract the bound names from a compojure-api binding vector body such as
    # `x :- Long, y :- (describe Long "..")`. A symbol followed by `:-` is a
    # bound name; the schema form after `:-` is skipped. Map-destructuring and
    # `&` rest-bindings are ignored.
    private def binding_param_names(source : String, start : Int32, limit : Int32) : Array(String)
      forms = [] of String
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        form_end = resource_end_of_value(source, i, limit)
        break if form_end <= i
        forms << source.byte_slice(i, form_end - i).strip
        i = form_end
      end

      names = [] of String
      j = 0
      while j < forms.size
        token = forms[j]
        if j + 1 < forms.size && forms[j + 1] == ":-"
          names << token if param_symbol?(token)
          j += 3 # name, `:-`, schema
        elsif token == "&"
          j += 2 # `&`, rest-binding name
        elsif token.starts_with?('{')
          # Optional param with default: `{y :- Long 1}` binds `y`.
          if name = optional_param_name(token)
            names << name
          end
          j += 1
        else
          names << token if param_symbol?(token)
          j += 1
        end
      end
      names.uniq
    end

    private def optional_param_name(token : String) : String?
      if m = token.match(/\A\{\s*([A-Za-z_][\w\-!?*<>]*)\s+:-/)
        m[1]
      end
    end

    private def param_symbol?(token : String) : Bool
      return false if token.empty?
      return false if token == ":-" || token.starts_with?(':')
      !!token.match(/\A[A-Za-z_][\w\-!?*<>]*\z/)
    end

    private def add_param_once(endpoint : Endpoint, name : String, param_type : String)
      return if name.empty?
      return if endpoint.params.any? { |p| p.name == name && p.param_type == param_type }
      endpoint.push_param(Param.new(name, "", param_type))
    end

    # `(resource {...})` (compojure.api.resource). The resource map keys the
    # HTTP methods it serves; the path is the enclosing context prefix. Returns
    # false when the first argument is not a map so the caller can fall back to
    # ordinary recursion. Each method value is itself a map that may carry a
    # `:handler`; a top-level `:handler` (no method key) serves every method.
    private def add_resource(source : String, args_start : Int32, form_end : Int32,
                             prefix : String, path : String, include_callee : Bool) : Bool
      i = skip_ws_and_comments(source, args_start, form_end)
      # An optional `^metadata` form may precede the resource map
      # (`(resource ^:foo {...})`); skip the metadata and its value.
      while i < form_end && source.byte_at(i).unsafe_chr == '^'
        i = resource_end_of_value(source, i + 1, form_end)
        i = skip_ws_and_comments(source, i, form_end)
      end
      return false if i >= form_end
      return false unless source.byte_at(i).unsafe_chr == '{'

      map_end = find_matching_delimiter(source, i, '{', '}', form_end)
      return false if map_end <= i

      route_path = prefix.empty? ? "/" : prefix
      data_handler = resource_value_range(source, i + 1, map_end, ":handler")

      method_found = false
      each_resource_entry(source, i + 1, map_end) do |key, key_pos, value_start, value_end|
        if method = RESOURCE_METHODS[key]?
          method_found = true
          handler_range = resource_value_range(source, value_start, value_end, ":handler") || data_handler
          emit_resource_endpoint(source, key_pos, route_path, method, path, include_callee, handler_range)
        end
      end

      if !method_found && (dh = data_handler)
        emit_resource_endpoint(source, dh[0], route_path, "GET", path, include_callee, dh)
      end

      true
    end

    private def emit_resource_endpoint(source : String, offset : Int32, route_path : String, method : String,
                                       path : String, include_callee : Bool, handler_range : Tuple(Int32, Int32)?)
      endpoint = Endpoint.new(route_path, method, Details.new(PathInfo.new(path, line_number_for(source, offset))))
      extract_path_param_names(route_path).each do |name|
        endpoint.push_param(Param.new(name, "", "path"))
      end

      if include_callee && handler_range
        body = source.byte_slice(handler_range[0], handler_range[1] - handler_range[0])
        start_line = line_number_for(source, handler_range[0])
        Noir::ClojureCalleeExtractor.attach_to(endpoint,
          Noir::ClojureCalleeExtractor.callees_for_body(body, path, start_line))
      end

      @result << endpoint
    end

    # Find the value byte-range of a top-level keyword key. When the scanned
    # span itself is a `{...}` map (a method-value map), descend into it; nested
    # values are skipped via `resource_end_of_value`.
    private def resource_value_range(source : String, start : Int32, limit : Int32, target_key : String) : Tuple(Int32, Int32)?
      i = skip_ws_and_comments(source, start, limit)
      return if i >= limit

      inner_start = i
      inner_limit = limit
      if source.byte_at(i).unsafe_chr == '{'
        map_end = find_matching_delimiter(source, i, '{', '}', limit)
        return if map_end <= i
        inner_start = i + 1
        inner_limit = map_end
      end

      result = nil.as(Tuple(Int32, Int32)?)
      each_resource_entry(source, inner_start, inner_limit) do |key, _key_pos, value_start, value_end|
        result = {value_start, value_end} if result.nil? && key == target_key
      end
      result
    end

    private def each_resource_entry(source : String, start : Int32, limit : Int32, &)
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        key_pos = i
        key, after_key = read_symbol(source, i, limit)
        if key.empty?
          i = resource_end_of_value(source, i, limit)
          next
        end

        value_start = skip_ws_and_comments(source, after_key, limit)
        break if value_start >= limit
        value_end = resource_end_of_value(source, value_start, limit)
        yield key, key_pos, value_start, value_end
        i = value_end
      end
    end

    private def resource_end_of_value(source : String, start : Int32, limit : Int32) : Int32
      i = skip_ws_and_comments(source, start, limit)
      return i if i >= limit

      case source.byte_at(i).unsafe_chr
      when '"'
        e = skip_string(source, i, limit)
        e >= i ? e + 1 : limit
      when '('
        e = find_matching_delimiter(source, i, '(', ')', limit)
        e > i ? e + 1 : limit
      when '['
        e = find_matching_delimiter(source, i, '[', ']', limit)
        e > i ? e + 1 : limit
      when '{'
        e = find_matching_delimiter(source, i, '{', '}', limit)
        e > i ? e + 1 : limit
      when '\'', '`'
        resource_end_of_value(source, i + 1, limit)
      when '#'
        nxt = i + 1 < limit ? source.byte_at(i + 1).unsafe_chr : '\0'
        case nxt
        when '{', '('
          inner_close = nxt == '{' ? '}' : ')'
          e = find_matching_delimiter(source, i + 1, nxt, inner_close, limit)
          e > i + 1 ? e + 1 : limit
        when '"'
          e = skip_string(source, i + 1, limit)
          e >= i + 1 ? e + 1 : limit
        when '_'
          resource_end_of_value(source, i + 2, limit)
        else
          _, after = read_symbol(source, i, limit)
          after
        end
      else
        _, after = read_symbol(source, i, limit)
        after > i ? after : i + 1
      end
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

    # Compojure allows an inline regex constraint on a path param:
    # `:id{[0-9]+}` binds `id` and validates it against `[0-9]+`. The
    # constraint is routing metadata, not part of the matched URL, so strip
    # it to keep the endpoint path clean (`/user/:id`, not `/user/:id{[0-9]+}`).
    private def normalize_route_path(route_path : String) : String
      route_path.gsub(/(:[A-Za-z_][\w\-]*)\{[^{}]*\}/, "\\1")
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

      # Compojure's `:<<` applies a coercion fn to the preceding binding,
      # e.g. `[id :<< as-int]` or `[x :<< #(Integer/parseInt %)]`. Neither the
      # operator nor the coercion fn names a request param, so drop both. A fn
      # written as an anonymous `#(...)` reader or a `(fn …)` form must be
      # stripped *before* the bare-symbol rule, otherwise the loose word
      # scanner would harvest the Java class/method names inside it
      # (`Integer`, `parseInt`). Handles one level of nested parens.
      inner_clean = inner_clean.gsub(/:<<\s*#?\([^()]*(?:\([^()]*\)[^()]*)*\)/, " ")
      inner_clean = inner_clean.gsub(/:<<\s+[^\s\[\]{}()]+/, " ")

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

    # The path argument of a route / `context` macro can be a plain string
    # (`"/foo"`) or a vector carrying inline regex constraints
    # (`["/foo/:id" :id #"[0-9]+"]`). For the vector form the path is its first
    # string literal; return the index of the closing `]` so binding/body
    # parsing resumes after the whole vector rather than inside it.
    private def route_path_literal(source : String, index : Int32, limit : Int32) : Tuple(String?, Int32)
      i = skip_ws_and_comments(source, index, limit)
      if i < limit && source.byte_at(i).unsafe_chr == '['
        vec_end = find_matching_delimiter(source, i, '[', ']', limit)
        return {nil, index} if vec_end <= i
        route_path, _ = first_string_literal(source, i + 1, vec_end)
        return {route_path, vec_end}
      end

      first_string_literal(source, index, limit)
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
        # Commas are whitespace in Clojure, so they terminate a symbol just
        # like spaces (keeps `[x, y]` from reading `x,` as one token).
        break if whitespace?(char) || char == ',' || {'(', ')', '[', ']', '{', '}', '"', ';'}.includes?(char)
        i += 1
      end

      {source.byte_slice(index, i - index), i}
    end

    private def skip_ws_and_comments(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit
        char = source.byte_at(i).unsafe_chr
        if whitespace?(char) || char == ','
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
