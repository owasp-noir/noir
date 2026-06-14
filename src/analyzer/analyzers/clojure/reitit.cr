require "../../../models/analyzer"
require "../../../miniparsers/clojure_callee_extractor"
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
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      all_files.each do |path|
        next unless clojure_file?(path)

        content = read_file_content(path)
        next unless reitit_source?(content)

        function_callees = include_callee ? Noir::ClojureCalleeExtractor.function_callees(content, path) : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)).new
        walk_forms(content, 0, content.bytesize, "", path, include_callee, function_callees)
      end

      Fiber.yield
      @result
    end

    private def clojure_file?(path : String) : Bool
      CLOJURE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
    end

    private def reitit_source?(content : String) : Bool
      # Any `reitit.*` namespace marks a reitit file. Route data is often
      # split across namespaces that only pull a coercion/middleware ns
      # (`reitit.coercion.spec`, `reitit.ring.coercion`, …) rather than the
      # core/ring/http entry points, so match the family broadly.
      content.includes?("reitit.") || content.includes?("metosin/reitit")
    end

    # Iterate forms looking for route-shaped vectors. A vector is
    # route-shaped if its first non-ws element is either a path
    # string (`"/...."`) or another route vector (a list of routes).
    private def walk_forms(source : String,
                           start : Int32,
                           limit : Int32,
                           prefix : String,
                           path : String,
                           include_callee : Bool,
                           function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
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
          walk_forms(source, i + 1, form_end, prefix, path, include_callee, function_callees)
          i = form_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          handled = try_process_routes(source, i, vec_end, prefix, path, include_callee, function_callees)
          walk_forms(source, i + 1, vec_end, prefix, path, include_callee, function_callees) unless handled
          i = vec_end + 1
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          walk_forms(source, i + 1, map_end, prefix, path, include_callee, function_callees)
          i = map_end + 1
        else
          i += 1
        end
      end
    end

    private def try_process_routes(source : String,
                                   vec_start : Int32,
                                   vec_end : Int32,
                                   prefix : String,
                                   path : String,
                                   include_callee : Bool,
                                   function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
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
        process_route_vec(source, vec_start, vec_end, prefix, path, include_callee, function_callees)
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
        process_route_list(source, inner_start, vec_end, prefix, path, include_callee, function_callees)
        true
      else
        false
      end
    end

    private def process_route_list(source : String,
                                   start : Int32,
                                   limit : Int32,
                                   prefix : String,
                                   path : String,
                                   include_callee : Bool,
                                   function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        c = source.byte_at(i).unsafe_chr
        if c == '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vec(source, i, vec_end, prefix, path, include_callee, function_callees)
          i = vec_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_vec(source : String,
                                  vec_start : Int32,
                                  vec_end : Int32,
                                  prefix : String,
                                  path : String,
                                  include_callee : Bool,
                                  function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = skip_ws_and_comments(source, vec_start + 1, vec_end)
      return if i >= vec_end
      return unless source.byte_at(i).unsafe_chr == '"'

      str_end = skip_string(source, i, vec_end)
      return if str_end <= i

      route_path = decode_string_literal(source.byte_slice(i, str_end - i + 1))
      new_prefix = join_path(prefix, route_path)

      # `["/path" handler]` — a bare handler (symbol / `#'var` / inline
      # `(fn …)`) in the data position is reitit shorthand for
      # `{:handler handler}` and responds to any method. Emit a GET endpoint so
      # the route is not dropped; a map / child-vector in that position is left
      # to walk_route_body.
      token, _ = read_form_token(source, str_end + 1, vec_end)
      if bare_route_handler?(token)
        handler_start = skip_ws_and_comments(source, str_end + 1, vec_end)
        handler_end = end_of_value(source, handler_start, vec_end)
        emit_endpoint(source, handler_start, handler_start, handler_end, new_prefix, "GET", path, include_callee, function_callees, nil)
      end

      walk_route_body(source, str_end + 1, vec_end, new_prefix, path, include_callee, function_callees)
    end

    # A bare route handler in the data position is an inline `(fn …)`/`(partial
    # …)` form, a `#'var`/`'sym` reference, or a plain handler symbol. Maps,
    # child-route vectors, strings and keywords are not handlers.
    private def bare_route_handler?(token : String) : Bool
      return false if token.empty?
      return true if token.starts_with?('(')
      !normalized_handler_symbol(token).nil?
    end

    private def walk_route_body(source : String,
                                start : Int32,
                                limit : Int32,
                                prefix : String,
                                path : String,
                                include_callee : Bool,
                                function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      i = start
      while i < limit
        i = skip_ws_and_comments(source, i, limit)
        break if i >= limit
        c = source.byte_at(i).unsafe_chr
        case c
        when '{'
          map_end = find_matching_delimiter(source, i, '{', '}', limit)
          break if map_end <= i
          process_route_data_map(source, i + 1, map_end, prefix, path, include_callee, function_callees)
          i = map_end + 1
        when '['
          vec_end = find_matching_delimiter(source, i, '[', ']', limit)
          break if vec_end <= i
          process_route_vec(source, i, vec_end, prefix, path, include_callee, function_callees)
          i = vec_end + 1
        else
          i = end_of_value(source, i, limit)
        end
      end
    end

    private def process_route_data_map(source : String,
                                       start : Int32,
                                       limit : Int32,
                                       route_path : String,
                                       path : String,
                                       include_callee : Bool,
                                       function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)))
      # A route-data-level `:handler` (sibling to the method keys) is the
      # handler reitit uses for any method without its own. Locate it first so
      # method endpoints can fall back to it and so a method-less `:handler`
      # still produces an endpoint.
      data_handler = find_value_range(source, start, limit, ":handler")

      method_found = false
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
          method_found = true
          emit_endpoint(source, key_start, v_start, val_end, route_path, method_name, path, include_callee, function_callees, data_handler)
        end

        i = val_end
      end

      # `["/path" {:handler h}]` (no method key) responds to every method.
      # Emit a single GET endpoint so the route is not dropped entirely.
      if !method_found && (dh = data_handler)
        emit_endpoint(source, dh[0], dh[0], dh[1], route_path, "GET", path, include_callee, function_callees, nil)
      end
    end

    # Find the value byte-range of a top-level `target_key` in a map at
    # `[start, limit)`. Nested maps are skipped via `end_of_value`, so only
    # first-level keys are inspected.
    private def find_value_range(source : String, start : Int32, limit : Int32, target_key : String) : Tuple(Int32, Int32)?
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

        return {v_start, val_end} if key == target_key
        i = val_end
      end
      nil
    end

    private def emit_endpoint(source : String, key_pos : Int32, v_start : Int32, v_end : Int32,
                              route_path : String,
                              method : String,
                              path : String,
                              include_callee : Bool,
                              function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)),
                              data_handler : Tuple(Int32, Int32)? = nil)
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

      attach_method_callees(endpoint, source, v_start, v_end, path, function_callees, data_handler) if include_callee

      @result << endpoint
    end

    private def attach_method_callees(endpoint : Endpoint,
                                      source : String,
                                      v_start : Int32,
                                      v_end : Int32,
                                      path : String,
                                      function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry)),
                                      data_handler : Tuple(Int32, Int32)? = nil)
      return if v_start >= v_end

      if source.byte_at(v_start).unsafe_chr == '{'
        map_end = find_matching_delimiter(source, v_start, '{', '}', v_end)
        return unless map_end > v_start
        attached = attach_handler_map_callees(source, v_start + 1, map_end, endpoint, path, function_callees)
        # `{:get {:parameters ...}}` carries no method-level handler; fall back
        # to the route-data `:handler` reitit would dispatch to.
        if !attached && (dh = data_handler)
          attach_handler_value(endpoint, source, dh[0], dh[1], path, function_callees)
        end
      else
        attach_handler_value(endpoint, source, v_start, v_end, path, function_callees)
      end
    end

    private def attach_handler_map_callees(source : String,
                                           start : Int32,
                                           limit : Int32,
                                           endpoint : Endpoint,
                                           path : String,
                                           function_callees : Hash(String, Array(Noir::ClojureCalleeExtractor::Entry))) : Bool
      attached = false
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

        if key == ":handler"
          attach_handler_value(endpoint, source, v_start, val_end, path, function_callees)
          attached = true
        end
        i = val_end
      end
      attached
    end

    private def attach_handler_value(endpoint : Endpoint,
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

      names = case source.byte_at(v_start).unsafe_chr
              when '{'
                # Schema / map literal: `{:x int?, (s/optional-key :y) int?}`.
                map_end = find_matching_delimiter(source, v_start, '{', '}', v_end)
                return unless map_end > v_start
                extract_map_keys(source, v_start + 1, map_end)
              when '['
                # malli map schema vector: `[:map [:x int?] [:y {…} int?]]`.
                vec_end = find_matching_delimiter(source, v_start, '[', ']', v_end)
                return unless vec_end > v_start
                extract_malli_map_keys(source, v_start + 1, vec_end)
              else
                return
              end

      names.each do |name|
        next if name.empty?
        next if ptype == "path" && path_param_set.includes?(name)
        next if endpoint.params.any? { |p| p.name == name && p.param_type == ptype }
        endpoint.push_param(Param.new(name, "", ptype))
      end
    end

    # Extract the entry keys of a malli map schema vector
    # `[:map [:x int?] [:y {:optional true} int?]]`. Only a `:map` head names
    # request params; other malli schemas (`[:maybe …]`, `[:vector …]`) are
    # positional and carry none. Each entry is a vector whose first keyword is
    # the key name; an optional properties map after `:map` is skipped.
    private def extract_malli_map_keys(source : String, start : Int32, limit : Int32) : Array(String)
      i = skip_ws_and_comments(source, start, limit)
      head, after_head = read_symbol(source, i, limit)
      return [] of String unless head == ":map"

      keys = [] of String
      j = after_head
      while j < limit
        j = skip_ws_and_comments(source, j, limit)
        break if j >= limit
        if source.byte_at(j).unsafe_chr == '['
          entry_end = find_matching_delimiter(source, j, '[', ']', limit)
          break if entry_end <= j
          if name = first_keyword_in(source, j + 1, entry_end)
            keys << name
          end
          j = entry_end + 1
        else
          j = end_of_value(source, j, limit)
        end
      end
      keys
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
            # A non-keyword key may still name a param when it's a schema /
            # malli wrapper — `(s/optional-key :page)`, `[:page {:optional
            # true}]`. Pull the first keyword inside the key form as the name.
            key_end = end_of_value(source, i, limit)
            if name = first_keyword_in(source, i, key_end)
              keys << name
            end
            i = skip_ws_and_comments(source, key_end, limit)
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

    # Return the bind name of the first keyword inside a key form. Schema
    # wraps optional/required keys (`(s/optional-key :page)`) and malli spells
    # them as vectors (`[:page {:optional true}]`); in both the parameter name
    # is the first keyword. Namespace-qualified keywords drop the namespace.
    private def first_keyword_in(source : String, start : Int32, limit : Int32) : String?
      i = start
      while i < limit
        if source.byte_at(i).unsafe_chr == ':'
          sym, _ = read_symbol(source, i, limit)
          name = sym.lstrip(':')
          if slash_idx = name.rindex('/')
            name = name[(slash_idx + 1)..]
          end
          return name unless name.empty?
        end
        i += 1
      end
      nil
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
