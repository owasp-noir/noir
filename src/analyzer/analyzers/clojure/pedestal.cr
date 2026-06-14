require "../../../models/analyzer"
require "../../../miniparsers/clojure_callee_extractor"
require "../../../utils/utils"

module Analyzer::Clojure
  class Pedestal < Analyzer
    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}

    HTTP_METHODS = {
      ":get"     => "GET",
      ":post"    => "POST",
      ":put"     => "PUT",
      ":patch"   => "PATCH",
      ":delete"  => "DELETE",
      ":head"    => "HEAD",
      ":options" => "OPTIONS",
      ":trace"   => "TRACE",
      ":connect" => "CONNECT",
      ":query"   => "QUERY",
      ":any"     => "ANY",
    }

    HELPER_METHODS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "patch"   => "PATCH",
      "delete"  => "DELETE",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      "trace"   => "TRACE",
      "connect" => "CONNECT",
      "any"     => "ANY",
    }

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      all_files.each do |path|
        next unless clojure_file?(path)

        content = read_file_content(path)
        next unless pedestal_source?(content)

        # Per-file dedup (the key has no path component); a shared set across
        # files drops legitimate same-method+route endpoints (and their params)
        # from every file after the first.
        seen = Set(String).new
        function_callees = include_callee ? Noir::ClojureCalleeExtractor.function_callees(content, path) : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)).new
        walk_forms(content, 0, content.bytesize, "", path, seen, include_callee, function_callees)
      end

      Fiber.yield
      @result
    end

    private def clojure_file?(path : String) : Bool
      CLOJURE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
    end

    private def pedestal_source?(content : String) : Bool
      content.includes?("io.pedestal") ||
        content.includes?("pedestal.service") ||
        content.includes?("pedestal.route") ||
        content.includes?("defroutes") ||
        content.includes?("table-routes")
    end

    private def walk_forms(source : String,
                           start : Int32,
                           limit : Int32,
                           prefix : String,
                           path : String,
                           seen : Set(String),
                           include_callee : Bool,
                           function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = start
      while i < limit
        case source.byte_at(i).unsafe_chr
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          i = skip_string(source, i, limit) + 1
        when '('
          form_end = find_matching_delimiter(source, i, '(', ')', limit)
          break if form_end <= i
          handled = process_list(source, i, form_end, prefix, path, seen, include_callee, function_callees)
          walk_forms(source, i + 1, form_end, prefix, path, seen, include_callee, function_callees) unless handled
          i = form_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          handled = process_route_vector(source, i, vec_end, prefix, path, seen, include_callee, function_callees)
          walk_forms(source, i + 1, vec_end, prefix, path, seen, include_callee, function_callees) unless handled
          i = vec_end + 1
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          handled = process_route_map(source, i, map_end, prefix, path, seen, include_callee, function_callees)
          walk_forms(source, i + 1, map_end, prefix, path, seen, include_callee, function_callees) unless handled
          i = map_end + 1
        else
          i += 1
        end
      end
    end

    private def process_list(source : String, list_start : Int32, list_end : Int32,
                             prefix : String,
                             path : String,
                             seen : Set(String),
                             include_callee : Bool,
                             function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
      sym_start = skip_ws_and_comments(source, list_start + 1, list_end)
      symbol, after_symbol = read_symbol(source, sym_start, list_end)
      return false if symbol.empty?

      base = base_symbol(symbol)
      if method = helper_method(symbol, base)
        route_path, route_literal_end = first_string_literal(source, after_symbol, list_end)
        # Pedestal route helpers take a literal path beginning with `/`
        # (`(route/get "/health" [] handler)`). A namespaced verb whose first
        # string is a full URL — `(client/post "http://host/api" ...)` from
        # clj-http/http-kit — or a log message — `(log/trace "writing event")`
        # — is not a route; let the walker descend over it instead of emitting
        # a phantom endpoint (`join_path` would otherwise force a leading `/`).
        if route_path && route_path.starts_with?("/")
          handler_range = helper_handler_range(source, route_literal_end + 1, list_end)
          emit_endpoint(source, list_start, join_path(prefix, route_path), method, path, seen, include_callee, function_callees, handler_range)
          true
        else
          false
        end
      elsif base == "table-routes"
        process_table_routes_call(source, after_symbol, list_end, prefix, path, seen, include_callee, function_callees)
        true
      elsif base == "describe-routes" || base == "routify" || base == "expand-routes" || base == "routes-from"
        walk_forms(source, after_symbol, list_end, prefix, path, seen, include_callee, function_callees)
        true
      else
        false
      end
    end

    private def helper_method(symbol : String, base : String) : String?
      return unless symbol.includes?("/")
      HELPER_METHODS[base]?
    end

    private def process_table_routes_call(source : String, start : Int32, limit : Int32,
                                          prefix : String,
                                          path : String,
                                          seen : Set(String),
                                          include_callee : Bool,
                                          function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = skip_ws_and_comments(source, start, limit)
      current_prefix = prefix

      if i < limit && source.byte_at(i).unsafe_chr == '{'
        map_end = find_matching_delimiter(source, i, '{', '}', limit)
        if map_end > i
          current_prefix = join_path(prefix, extract_context(source, i + 1, map_end) || "")
          i = map_end + 1
        end
      end

      i = skip_ws_and_comments(source, i, limit)
      if i < limit && source.byte_at(i).unsafe_chr == '['
        vec_end = find_matching_delimiter(source, i, '[', ']', limit)
        if vec_end > i
          process_table_route_entries(source, i + 1, vec_end, current_prefix, path, seen, include_callee, function_callees)
          return
        end
      elsif i + 1 < limit && source.byte_at(i).unsafe_chr == '#' && source.byte_at(i + 1).unsafe_chr == '{'
        set_end = find_matching_delimiter(source, i + 1, '{', '}', limit)
        if set_end > i + 1
          process_table_route_entries(source, i + 2, set_end, current_prefix, path, seen, include_callee, function_callees)
          return
        end
      end

      walk_forms(source, i, limit, current_prefix, path, seen, include_callee, function_callees)
    end

    private def process_table_route_entries(source : String, start : Int32, limit : Int32,
                                            prefix : String,
                                            path : String,
                                            seen : Set(String),
                                            include_callee : Bool,
                                            function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = start
      current_prefix = prefix
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit

        case source.byte_at(i).unsafe_chr
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vector(source, i, vec_end, current_prefix, path, seen, include_callee, function_callees)
          i = vec_end + 1
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          if context = extract_context(source, i + 1, map_end)
            current_prefix = join_path(prefix, context)
          else
            process_route_map(source, i, map_end, current_prefix, path, seen, include_callee, function_callees)
          end
          i = map_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_vector(source : String, vec_start : Int32, vec_end : Int32,
                                     prefix : String,
                                     path : String,
                                     seen : Set(String),
                                     include_callee : Bool,
                                     function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
      i = skip_ws_and_comments(source, vec_start + 1, vec_end)
      if i >= vec_end || source.byte_at(i).unsafe_chr != '"'
        if prefix.starts_with?("/")
          walk_route_vector_body(source, i, vec_end, prefix, path, seen, include_callee, function_callees)
          return true
        end

        return false
      end

      str_end = skip_string(source, i, vec_end)
      return false if str_end <= i

      route_path = decode_string_literal(source.byte_slice(i, str_end - i + 1))
      return false unless route_path.starts_with?("/")

      full_path = join_path(prefix, route_path)
      body_start = skip_ws_and_comments(source, str_end + 1, vec_end)
      return true if body_start >= vec_end

      value_end = end_of_value(source, body_start, vec_end)
      if value_end > body_start
        token = source.byte_slice(body_start, value_end - body_start)
        if method = route_method(token)
          handler_range = next_value_range(source, value_end, vec_end)
          emit_endpoint(source, body_start, full_path, method, path, seen, include_callee, function_callees, handler_range)
          return true
        end
      end

      walk_route_vector_body(source, body_start, vec_end, full_path, path, seen, include_callee, function_callees)
      true
    end

    private def walk_route_vector_body(source : String, start : Int32, limit : Int32,
                                       route_path : String,
                                       path : String,
                                       seen : Set(String),
                                       include_callee : Bool,
                                       function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit

        case source.byte_at(i).unsafe_chr
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          process_method_map(source, i + 1, map_end, route_path, path, seen, include_callee, function_callees)
          process_route_map(source, i, map_end, route_path, path, seen, include_callee, function_callees)
          i = map_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vector(source, i, vec_end, route_path, path, seen, include_callee, function_callees)
          i = vec_end + 1
        when '('
          form_end = find_matching_delimiter(source, i, '(', ')', limit)
          break if form_end <= i
          handled = process_list(source, i, form_end, route_path, path, seen, include_callee, function_callees)
          walk_forms(source, i + 1, form_end, route_path, path, seen, include_callee, function_callees) unless handled
          i = form_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_map(source : String, map_start : Int32, map_end : Int32,
                                  prefix : String,
                                  path : String,
                                  seen : Set(String),
                                  include_callee : Bool,
                                  function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
      context_prefix = join_path(prefix, extract_context(source, map_start + 1, map_end) || "")
      verbose = process_verbose_map(source, map_start + 1, map_end, context_prefix, path, seen, include_callee, function_callees)
      path_keyed = process_path_keyed_map(source, map_start + 1, map_end, context_prefix, path, seen, include_callee, function_callees)
      verbose || path_keyed
    end

    private def process_verbose_map(source : String, start : Int32, limit : Int32,
                                    prefix : String,
                                    path : String,
                                    seen : Set(String),
                                    include_callee : Bool,
                                    function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
      route_path = nil.as(String?)
      route_method = nil.as(String?)
      method_pos = start
      verbs_range = nil.as(Tuple(Int32, Int32)?)
      children_range = nil.as(Tuple(Int32, Int32)?)

      each_map_entry(source, start, limit) do |key, key_pos, value_start, value_end|
        case key
        when ":path"
          if value_start < value_end && source.byte_at(value_start).unsafe_chr == '"'
            str_end = skip_string(source, value_start, value_end)
            route_path = decode_string_literal(source.byte_slice(value_start, str_end - value_start + 1))
          end
        when ":verbs"
          verbs_range = {value_start, value_end}
        when ":method"
          token, _ = read_form_token(source, value_start, value_end)
          if method = route_method(token)
            route_method = method
            method_pos = key_pos
          end
        when ":children"
          children_range = {value_start, value_end}
        end
      end

      route_path_value = route_path
      return false unless route_path_value

      full_path = join_path(prefix, route_path_value)
      if range = verbs_range
        v_start, v_end = range
        if v_start < v_end && source.byte_at(v_start).unsafe_chr == '{'
          process_method_map(source, v_start + 1, v_end - 1, full_path, path, seen, include_callee, function_callees)
        end
      elsif method = route_method
        emit_endpoint(source, method_pos, full_path, method, path, seen, include_callee, function_callees, nil)
      end

      if range = children_range
        c_start, c_end = range
        walk_forms(source, c_start, c_end, full_path, path, seen, include_callee, function_callees)
      end

      true
    end

    private def process_path_keyed_map(source : String, start : Int32, limit : Int32,
                                       prefix : String,
                                       path : String,
                                       seen : Set(String),
                                       include_callee : Bool,
                                       function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
      handled = false
      each_map_entry(source, start, limit) do |key, key_pos, value_start, value_end|
        next unless key.starts_with?('"') && key.ends_with?('"')
        route_path = decode_string_literal(key)
        next unless route_path.starts_with?("/")
        handled = true

        full_path = join_path(prefix, route_path)
        if value_start < value_end
          case source.byte_at(value_start).unsafe_chr
          when '{'
            process_method_map(source, value_start + 1, value_end - 1, full_path, path, seen, include_callee, function_callees)
            process_path_keyed_map(source, value_start + 1, value_end - 1, full_path, path, seen, include_callee, function_callees)
          when '['
            walk_forms(source, value_start, value_end, full_path, path, seen, include_callee, function_callees)
          else
            emit_endpoint(source, key_pos, full_path, "ANY", path, seen, include_callee, function_callees, {value_start, value_end})
          end
        end
      end
      handled
    end

    private def process_method_map(source : String, start : Int32, limit : Int32,
                                   route_path : String,
                                   path : String,
                                   seen : Set(String),
                                   include_callee : Bool,
                                   function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      each_map_entry(source, start, limit) do |key, key_pos, value_start, value_end|
        if method = standard_method(key)
          emit_endpoint(source, key_pos, route_path, method, path, seen, include_callee, function_callees, {value_start, value_end})
        end
      end
    end

    private def standard_method(token : String) : String?
      HTTP_METHODS[token]?
    end

    private def route_method(token : String) : String?
      standard_method(token)
    end

    private def each_map_entry(source : String, start : Int32, limit : Int32, &)
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit

        key_pos = i
        key, after_key = read_form_token(source, i, limit)
        break if key.empty?

        value_start = skip_ws_and_comments(source, after_key, limit)
        break if value_start >= limit
        value_end = end_of_value(source, value_start, limit)
        yield key, key_pos, value_start, value_end
        i = value_end
      end
    end

    private def emit_endpoint(source : String, offset : Int32, route_path : String, method : String,
                              path : String,
                              seen : Set(String),
                              include_callee : Bool,
                              function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)),
                              handler_range : Tuple(Int32, Int32)?)
      return unless route_path.starts_with?("/")
      key = "#{method}::#{route_path}"
      return if seen.includes?(key)
      seen << key

      endpoint = Endpoint.new(route_path, method, Details.new(PathInfo.new(path, line_number_for(source, offset))))
      extract_path_param_names(route_path).each do |name|
        add_param_once(endpoint, name, "path")
      end
      if include_callee && handler_range
        attach_handler_callees(endpoint, source, handler_range[0], handler_range[1], path, function_callees)
      end
      @result << endpoint
    end

    private def helper_handler_range(source : String, start : Int32, limit : Int32) : Tuple(Int32, Int32)?
      # Pedestal helper routes are usually `(route/get "/path" [] handler)`.
      first = next_value_range(source, start, limit)
      return unless first
      next_value_range(source, first[1], limit)
    end

    private def next_value_range(source : String, start : Int32, limit : Int32) : Tuple(Int32, Int32)?
      value_start = skip_ws_and_comments(source, start, limit)
      return if value_start >= limit
      value_end = end_of_value(source, value_start, limit)
      return if value_end <= value_start
      {value_start, value_end}
    end

    private def attach_handler_callees(endpoint : Endpoint,
                                       source : String,
                                       value_start : Int32,
                                       value_end : Int32,
                                       path : String,
                                       function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      token, _ = read_form_token(source, value_start, value_end)
      return if token.empty?

      if token.starts_with?('(')
        body = source.byte_slice(value_start, value_end - value_start)
        line = line_number_for(source, value_start)
        Noir::ClojureCalleeExtractor.attach_to(endpoint, Noir::ClojureCalleeExtractor.callees_for_body(body, path, line))
      elsif handler_name = normalized_handler_symbol(token)
        if callees = function_callees[handler_name]?
          Noir::ClojureCalleeExtractor.attach_to(endpoint, callees)
        else
          endpoint.push_callee(Callee.new(handler_name, path: path, line: line_number_for(source, value_start)))
        end
      end
    end

    private def normalized_handler_symbol(token : String) : String?
      name = token
      if name.starts_with?("#'")
        name = name[2..]
      elsif name.starts_with?('\'') || name.starts_with?('`')
        name = name[1..]
      end

      return unless handler_symbol?(name)
      function_name(name)
    end

    private def handler_symbol?(token : String) : Bool
      return false if token.starts_with?(':')
      return false if token.starts_with?('"')
      return false if {"nil", "true", "false"}.includes?(token)
      !!token.match(/^[A-Za-z_.*+!?<>=][\w.\-*+!?<>=\/]*$/)
    end

    private def function_name(symbol : String) : String
      if index = symbol.rindex('/')
        symbol[(index + 1)..]
      else
        symbol
      end
    end

    private def add_param_once(endpoint : Endpoint, name : String, param_type : String)
      return if endpoint.params.any? { |p| p.name == name && p.param_type == param_type }
      endpoint.push_param(Param.new(name, "", param_type))
    end

    private def extract_path_param_names(route_path : String) : Array(String)
      names = [] of String
      route_path.scan(/[:*]([A-Za-z_][\w\-]*)/) do |match|
        name = match[1]
        names << name unless names.includes?(name)
      end
      names
    end

    private def extract_context(source : String, start : Int32, limit : Int32) : String?
      each_map_entry(source, start, limit) do |key, _key_pos, value_start, value_end|
        next unless {":context", ":io.pedestal.http/context", "::http/context"}.includes?(key)
        next unless value_start < value_end && source.byte_at(value_start).unsafe_chr == '"'
        str_end = skip_string(source, value_start, value_end)
        return decode_string_literal(source.byte_slice(value_start, str_end - value_start + 1))
      end
      nil
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

    private def read_form_token(source : String, start : Int32, limit : Int32) : Tuple(String, Int32)
      i = skip_ws_and_comments(source, start, limit)
      return {"", i} if i >= limit

      case source.byte_at(i).unsafe_chr
      when '"'
        e = skip_string(source, i, limit)
        {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)}
      when '('
        e = find_matching_delimiter(source, i, '(', ')', limit)
        e > i ? {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)} : {"", i}
      when '['
        e = find_matching_delimiter(source, i, '[', ']', limit)
        e > i ? {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)} : {"", i}
      when '{'
        e = find_matching_delimiter(source, i, '{', '}', limit)
        e > i ? {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)} : {"", i}
      else
        read_symbol(source, i, limit)
      end
    end

    private def end_of_value(source : String, start : Int32, limit : Int32) : Int32
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
      when '\'', '`', '^'
        end_of_value(source, i + 1, limit)
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
          end_of_value(source, i + 2, limit)
        else
          _, after = read_symbol(source, i, limit)
          after
        end
      else
        _, after = read_symbol(source, i, limit)
        after > i ? after : i + 1
      end
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
        break if whitespace?(char) || {',', '(', ')', '[', ']', '{', '}', '"', ';'}.includes?(char)
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
