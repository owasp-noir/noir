require "../../../models/analyzer"
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
      seen = Set(String).new
      all_files.each do |path|
        next unless clojure_file?(path)

        content = read_file_content(path)
        next unless pedestal_source?(content)

        walk_forms(content, 0, content.bytesize, "", path, seen)
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

    private def walk_forms(source : String, start : Int32, limit : Int32, prefix : String, path : String, seen : Set(String))
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
          handled = process_list(source, i, form_end, prefix, path, seen)
          walk_forms(source, i + 1, form_end, prefix, path, seen) unless handled
          i = form_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          handled = process_route_vector(source, i, vec_end, prefix, path, seen)
          walk_forms(source, i + 1, vec_end, prefix, path, seen) unless handled
          i = vec_end + 1
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          handled = process_route_map(source, i, map_end, prefix, path, seen)
          walk_forms(source, i + 1, map_end, prefix, path, seen) unless handled
          i = map_end + 1
        else
          i += 1
        end
      end
    end

    private def process_list(source : String, list_start : Int32, list_end : Int32,
                             prefix : String, path : String, seen : Set(String)) : Bool
      sym_start = skip_ws_and_comments(source, list_start + 1, list_end)
      symbol, after_symbol = read_symbol(source, sym_start, list_end)
      return false if symbol.empty?

      base = base_symbol(symbol)
      if method = helper_method(symbol, base)
        route_path, _ = first_string_literal(source, after_symbol, list_end)
        emit_endpoint(source, list_start, join_path(prefix, route_path), method, path, seen) if route_path
        true
      elsif base == "table-routes"
        process_table_routes_call(source, after_symbol, list_end, prefix, path, seen)
        true
      elsif base == "describe-routes" || base == "routify" || base == "expand-routes" || base == "routes-from"
        walk_forms(source, after_symbol, list_end, prefix, path, seen)
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
                                          prefix : String, path : String, seen : Set(String))
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
          process_table_route_entries(source, i + 1, vec_end, current_prefix, path, seen)
          return
        end
      elsif i + 1 < limit && source.byte_at(i).unsafe_chr == '#' && source.byte_at(i + 1).unsafe_chr == '{'
        set_end = find_matching_delimiter(source, i + 1, '{', '}', limit)
        if set_end > i + 1
          process_table_route_entries(source, i + 2, set_end, current_prefix, path, seen)
          return
        end
      end

      walk_forms(source, i, limit, current_prefix, path, seen)
    end

    private def process_table_route_entries(source : String, start : Int32, limit : Int32,
                                            prefix : String, path : String, seen : Set(String))
      i = start
      current_prefix = prefix
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit

        case source.byte_at(i).unsafe_chr
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vector(source, i, vec_end, current_prefix, path, seen)
          i = vec_end + 1
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          if context = extract_context(source, i + 1, map_end)
            current_prefix = join_path(prefix, context)
          else
            process_route_map(source, i, map_end, current_prefix, path, seen)
          end
          i = map_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_vector(source : String, vec_start : Int32, vec_end : Int32,
                                     prefix : String, path : String, seen : Set(String)) : Bool
      i = skip_ws_and_comments(source, vec_start + 1, vec_end)
      return false if i >= vec_end || source.byte_at(i).unsafe_chr != '"'

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
        if method = HTTP_METHODS[token]?
          emit_endpoint(source, body_start, full_path, method, path, seen)
          return true
        end
      end

      walk_route_vector_body(source, body_start, vec_end, full_path, path, seen)
      true
    end

    private def walk_route_vector_body(source : String, start : Int32, limit : Int32,
                                       route_path : String, path : String, seen : Set(String))
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit

        case source.byte_at(i).unsafe_chr
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          process_method_map(source, i + 1, map_end, route_path, path, seen)
          process_route_map(source, i, map_end, route_path, path, seen)
          i = map_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vector(source, i, vec_end, route_path, path, seen)
          i = vec_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_map(source : String, map_start : Int32, map_end : Int32,
                                  prefix : String, path : String, seen : Set(String)) : Bool
      context_prefix = join_path(prefix, extract_context(source, map_start + 1, map_end) || "")
      verbose = process_verbose_map(source, map_start + 1, map_end, context_prefix, path, seen)
      path_keyed = process_path_keyed_map(source, map_start + 1, map_end, context_prefix, path, seen)
      verbose || path_keyed
    end

    private def process_verbose_map(source : String, start : Int32, limit : Int32,
                                    prefix : String, path : String, seen : Set(String)) : Bool
      route_path = nil.as(String?)
      path_pos = start
      verbs_range = nil.as(Tuple(Int32, Int32)?)
      children_range = nil.as(Tuple(Int32, Int32)?)

      each_map_entry(source, start, limit) do |key, key_pos, value_start, value_end|
        case key
        when ":path"
          if value_start < value_end && source.byte_at(value_start).unsafe_chr == '"'
            str_end = skip_string(source, value_start, value_end)
            route_path = decode_string_literal(source.byte_slice(value_start, str_end - value_start + 1))
            path_pos = key_pos
          end
        when ":verbs"
          verbs_range = {value_start, value_end}
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
          process_method_map(source, v_start + 1, v_end - 1, full_path, path, seen)
        end
      end

      if range = children_range
        c_start, c_end = range
        walk_forms(source, c_start, c_end, full_path, path, seen)
      end

      emit_endpoint(source, path_pos, full_path, "ANY", path, seen) unless verbs_range
      true
    end

    private def process_path_keyed_map(source : String, start : Int32, limit : Int32,
                                       prefix : String, path : String, seen : Set(String)) : Bool
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
            process_method_map(source, value_start + 1, value_end - 1, full_path, path, seen)
            process_path_keyed_map(source, value_start + 1, value_end - 1, full_path, path, seen)
          when '['
            walk_forms(source, value_start, value_end, full_path, path, seen)
          else
            emit_endpoint(source, key_pos, full_path, "ANY", path, seen)
          end
        end
      end
      handled
    end

    private def process_method_map(source : String, start : Int32, limit : Int32,
                                   route_path : String, path : String, seen : Set(String))
      each_map_entry(source, start, limit) do |key, key_pos, _value_start, _value_end|
        if method = HTTP_METHODS[key]?
          emit_endpoint(source, key_pos, route_path, method, path, seen)
        end
      end
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
                              path : String, seen : Set(String))
      return unless route_path.starts_with?("/")
      key = "#{method}::#{route_path}"
      return if seen.includes?(key)
      seen << key

      endpoint = Endpoint.new(route_path, method, Details.new(PathInfo.new(path, line_number_for(source, offset))))
      extract_path_param_names(route_path).each do |name|
        add_param_once(endpoint, name, "path")
      end
      @result << endpoint
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
