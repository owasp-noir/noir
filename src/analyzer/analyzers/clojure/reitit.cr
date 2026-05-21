require "../../../models/analyzer"
require "../../../utils/utils"

module Analyzer::Clojure
  # Reitit is data-driven: routes are a vector tree
  # `["/prefix" {:get {...}} ["/child" {:post {...}}] ...]`
  # rather than nested macro calls. The walker descends through
  # vectors, accumulating the prefix, and pulls method handlers
  # out of the route-data map keyed by `:get`/`:post`/etc.
  class Reitit < Analyzer
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

    PARAM_GROUPS = {
      ":query"  => "query",
      ":path"   => "path",
      ":header" => "header",
      ":body"   => "json",
      ":form"   => "form",
    }

    def analyze
      all_files.each do |path|
        next unless clojure_file?(path)

        content = read_file_content(path)
        next unless reitit_source?(content)

        walk_forms(content, 0, content.bytesize, "", path)
      end

      Fiber.yield
      @result
    end

    private def clojure_file?(path : String) : Bool
      CLOJURE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
    end

    private def reitit_source?(content : String) : Bool
      content.includes?("reitit.core") ||
        content.includes?("reitit.ring") ||
        content.includes?("reitit.http") ||
        content.includes?("metosin/reitit")
    end

    # Iterate forms looking for route-shaped vectors. A vector is
    # route-shaped if its first non-ws element is either a path
    # string (`"/...."`) or another route vector (a list of routes).
    private def walk_forms(source : String, start : Int32, limit : Int32, prefix : String, path : String)
      i = start
      while i < limit
        c = source.byte_at(i).unsafe_chr
        case c
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          i = skip_string(source, i, limit) + 1
        when '('
          form_end = find_matching_delimiter(source, i, '(', ')', limit)
          break if form_end <= i
          walk_forms(source, i + 1, form_end, prefix, path)
          i = form_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          handled = try_process_routes(source, i, vec_end, prefix, path)
          walk_forms(source, i + 1, vec_end, prefix, path) unless handled
          i = vec_end + 1
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          walk_forms(source, i + 1, map_end, prefix, path)
          i = map_end + 1
        else
          i += 1
        end
      end
    end

    private def try_process_routes(source : String, vec_start : Int32, vec_end : Int32, prefix : String, path : String) : Bool
      inner_start = vec_start + 1
      i = skip_ws_and_comments(source, inner_start, vec_end)
      return false if i >= vec_end

      case source.byte_at(i).unsafe_chr
      when '"'
        # Single route node: ["/path" ...body]
        str_end = skip_string(source, i, vec_end)
        return false if str_end <= i
        route_path = decode_string_literal(source.byte_slice(i, str_end - i + 1))
        return false unless route_path.starts_with?("/")
        process_route_vec(source, vec_start, vec_end, prefix, path)
        true
      when '['
        # List of routes: [["/a" ...] ["/b" ...]]
        child_end = find_matching_delimiter(source, i, '[', ']', vec_end)
        return false if child_end <= i
        j = skip_ws_and_comments(source, i + 1, child_end)
        return false if j >= child_end
        return false unless source.byte_at(j).unsafe_chr == '"'
        str_end = skip_string(source, j, child_end)
        return false if str_end <= j
        peek = decode_string_literal(source.byte_slice(j, str_end - j + 1))
        return false unless peek.starts_with?("/")
        process_route_list(source, inner_start, vec_end, prefix, path)
        true
      else
        false
      end
    end

    private def process_route_list(source : String, start : Int32, limit : Int32, prefix : String, path : String)
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        c = source.byte_at(i).unsafe_chr
        if c == '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vec(source, i, vec_end, prefix, path)
          i = vec_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_vec(source : String, vec_start : Int32, vec_end : Int32, prefix : String, path : String)
      i = skip_ws_and_comments(source, vec_start + 1, vec_end)
      return if i >= vec_end
      return unless source.byte_at(i).unsafe_chr == '"'

      str_end = skip_string(source, i, vec_end)
      return if str_end <= i

      route_path = decode_string_literal(source.byte_slice(i, str_end - i + 1))
      new_prefix = join_path(prefix, route_path)
      walk_route_body(source, str_end + 1, vec_end, new_prefix, path)
    end

    private def walk_route_body(source : String, start : Int32, limit : Int32, prefix : String, path : String)
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        c = source.byte_at(i).unsafe_chr
        case c
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          process_route_data_map(source, i + 1, map_end, prefix, path)
          i = map_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vec(source, i, vec_end, prefix, path)
          i = vec_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_data_map(source : String, start : Int32, limit : Int32, route_path : String, path : String)
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        key_start = i
        key, after_key = read_symbol(source, i, limit)
        if key.empty?
          i = end_of_value(source, i, limit)
          next
        end

        v_start = skip_ws_and_comments(source, after_key, limit)
        break if v_start >= limit
        val_end = end_of_value(source, v_start, limit)

        if method_name = HTTP_METHODS[key]?
          emit_endpoint(source, key_start, v_start, val_end, route_path, method_name, path)
        end

        i = val_end
      end
    end

    private def emit_endpoint(source : String, key_pos : Int32, v_start : Int32, v_end : Int32,
                              route_path : String, method : String, path : String)
      endpoint = Endpoint.new(route_path, method, Details.new(PathInfo.new(path, line_number_for(source, key_pos))))

      extract_path_param_names(route_path).each do |name|
        endpoint.push_param(Param.new(name, "", "path"))
      end

      if v_start < v_end && source.byte_at(v_start).unsafe_chr == '{'
        map_end = find_matching_delimiter(source, v_start, '{', '}', v_end)
        if map_end > v_start
          extract_params_from_method_map(source, v_start + 1, map_end, endpoint, route_path)
        end
      end

      @result << endpoint
    end

    private def extract_params_from_method_map(source : String, start : Int32, limit : Int32,
                                               endpoint : Endpoint, route_path : String)
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        key, after_key = read_symbol(source, i, limit)
        if key.empty?
          i = end_of_value(source, i, limit)
          next
        end

        v_start = skip_ws_and_comments(source, after_key, limit)
        break if v_start >= limit
        val_end = end_of_value(source, v_start, limit)

        if key == ":parameters" && v_start < val_end && source.byte_at(v_start).unsafe_chr == '{'
          map_end = find_matching_delimiter(source, v_start, '{', '}', val_end)
          if map_end > v_start
            extract_param_groups(source, v_start + 1, map_end, endpoint, route_path)
          end
        end

        i = val_end
      end
    end

    private def extract_param_groups(source : String, start : Int32, limit : Int32,
                                     endpoint : Endpoint, route_path : String)
      path_param_set = extract_path_param_names(route_path).to_set
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        key, after_key = read_symbol(source, i, limit)
        if key.empty?
          i = end_of_value(source, i, limit)
          next
        end

        v_start = skip_ws_and_comments(source, after_key, limit)
        break if v_start >= limit
        val_end = end_of_value(source, v_start, limit)

        if ptype = PARAM_GROUPS[key]?
          add_group_params(source, v_start, val_end, endpoint, ptype, path_param_set)
        end

        i = val_end
      end
    end

    private def add_group_params(source : String, v_start : Int32, v_end : Int32,
                                 endpoint : Endpoint, ptype : String, path_param_set : Set(String))
      return if v_start >= v_end
      return unless source.byte_at(v_start).unsafe_chr == '{'

      map_end = find_matching_delimiter(source, v_start, '{', '}', v_end)
      return unless map_end > v_start

      extract_map_keys(source, v_start + 1, map_end).each do |name|
        next if name.empty?
        next if ptype == "path" && path_param_set.includes?(name)
        next if endpoint.params.any? { |p| p.name == name && p.param_type == ptype }
        endpoint.push_param(Param.new(name, "", ptype))
      end
    end

    # Extract first-level keyword keys (`:foo`, `:ns/foo`) from a map
    # literal at `[start, limit)`. Values are skipped — only the bind
    # name (segment after the last `/`) is recorded.
    private def extract_map_keys(source : String, start : Int32, limit : Int32) : Array(String)
      keys = [] of String
      i = start
      expect_key = true
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit

        if expect_key
          c = source.byte_at(i).unsafe_chr
          if c == ':'
            sym, after = read_symbol(source, i, limit)
            name = sym.lstrip(':')
            if slash_idx = name.rindex('/')
              name = name[(slash_idx + 1)..]
            end
            keys << name unless name.empty?
            i = after
          else
            # Non-keyword key — skip it and the value pair.
            i = end_of_value(source, i, limit)
            i = skip_ws_and_comments(source, i, limit)
            break if i >= limit
            i = end_of_value(source, i, limit)
            next
          end
          expect_key = false
        else
          i = end_of_value(source, i, limit)
          expect_key = true
        end
      end
      keys
    end

    private def extract_path_param_names(route_path : String) : Array(String)
      names = [] of String
      route_path.scan(/:([A-Za-z_][\w\-]*)/) do |match|
        names << match[1]
      end
      names
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
      when '\'', '`'
        end_of_value(source, i + 1, limit)
      when '#'
        # Reader macros: `#{set}`, `#"regex"`, `#_form`, `#(fn ...)`.
        nxt = i + 1 < limit ? source.byte_at(i + 1).unsafe_chr : '\0'
        case nxt
        when '{', '('
          inner_open = nxt
          inner_close = nxt == '{' ? '}' : ')'
          e = find_matching_delimiter(source, i + 1, inner_open, inner_close, limit)
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
        elsif char == ','
          # Clojure treats commas as whitespace.
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
