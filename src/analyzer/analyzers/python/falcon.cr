require "../../engines/python_engine"

module Analyzer::Python
  class Falcon < PythonEngine
    # Reference: https://falcon.readthedocs.io/en/stable/user/tutorial.html
    #
    # Falcon is a class-based REST framework. Routes are registered with
    # `app.add_route('/path', ResourceInstance())` where the resource class
    # defines responder methods named `on_get`, `on_post`, `on_put`,
    # `on_delete`, `on_patch`, `on_head`, `on_options`. A `suffix=` keyword
    # allows a single class to serve multiple routes via e.g. `on_get_item`.
    #
    # Parameter access inside a responder:
    #   req.get_param("key") / req.params["key"]   → query
    #   req.get_header("X-Key")                    → header
    #   req.cookies["name"] / req.get_cookie_values(…) → cookie
    #   req.media / await req.get_media()          → json (body)
    #   req.bounded_stream                         → form (raw body stream)

    RESPONDER_METHODS = {
      "on_get"     => "GET",
      "on_post"    => "POST",
      "on_put"     => "PUT",
      "on_delete"  => "DELETE",
      "on_patch"   => "PATCH",
      "on_head"    => "HEAD",
      "on_options" => "OPTIONS",
    }

    @keyword_regex_cache = Hash(::String, Regex).new
    @media_var_regex_cache = Hash(::String, Tuple(Regex, Regex)).new

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        python_files.each do |path|
          next unless path_under_root?(path, current_base_path)
          next if path.includes?("/site-packages/")
          next if python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          analyze_file(path, current_base_path)
        end
      end

      result
    end

    private def analyze_file(path : ::String, definition_base_path : ::String)
      source = read_file_content(path)
      lines = source.lines
      return unless lines.any?(&.includes?("falcon"))

      routes = [] of Tuple(Int32, ::String, ::String, ::String)
      classes = Hash(::String, Int32).new
      resource_instances = Hash(::String, ::String).new
      import_map = find_imported_modules(definition_base_path, path, source)
      source_cache = Hash(::String, ::String).new
      source_cache[path] = source
      class_cache = Hash(::String, Hash(::String, Int32)).new

      lines.each_with_index do |line, line_index|
        # Record class definitions for later responder lookup.
        if class_match = line.match(/^\s*class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[\(:]/)
          classes[class_match[1]] = line_index
        end

        if instance_match = line.match(/^\s*([a-zA-Z_][a-zA-Z0-9_]*)(?::[^=]+)?\s*=\s*((?:[a-zA-Z_][a-zA-Z0-9_]*\.)*[a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
          instance_name = instance_match[1]
          resource_ref = instance_match[2]
          resource_instances[instance_name] = resource_ref
        end

        # `xxx.add_route('/path', ResourceClass(), suffix='item')`
        #
        # Multi-line variants:
        #   app.add_route(
        #     "/path",
        #     ResourceClass(),
        #   )
        #
        # Keyword variants (Falcon 2/3+):
        #   app.add_route(uri_template="/path", resource=ResourceClass())
        #
        # Coalesce continuation lines so the path/class regex sees
        # them on the same logical line, then run the existing
        # positional regex *and* a keyword-form regex.
        if line.includes?(".add_route") && line.includes?("(")
          effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, line_index, line) : line

          route_match = effective_line.match(/\.add_route\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*((?:[a-zA-Z_][a-zA-Z0-9_]*\.)*[a-zA-Z_][a-zA-Z0-9_]*)/)
          if route_match
            route_path = route_match[1]
            resource_ref = route_match[2]
            suffix = ""
            if suffix_match = effective_line.match(/suffix\s*=\s*['"]([^'"]*)['"]/)
              suffix = suffix_match[1]
            end
            routes << {line_index, route_path, resource_ref, suffix}
          else
            # Keyword form. `uri_template=` / `path=` for the path
            # (`path=` accepted because some Falcon helper APIs and
            # older docs use it interchangeably); `resource=` for the
            # responder.
            kw_path_match = effective_line.match(/(?:uri_template|path)\s*=\s*[rf]?['"]([^'"]*)['"]/)
            kw_resource_match = effective_line.match(/resource\s*=\s*((?:[a-zA-Z_][a-zA-Z0-9_]*\.)*[a-zA-Z_][a-zA-Z0-9_]*)/)
            if kw_path_match && kw_resource_match
              route_path = kw_path_match[1]
              resource_ref = kw_resource_match[1]
              suffix = ""
              if suffix_match = effective_line.match(/suffix\s*=\s*['"]([^'"]*)['"]/)
                suffix = suffix_match[1]
              end
              routes << {line_index, route_path, resource_ref, suffix}
            end
          end
        end

        if line.includes?(".add_static_route") && line.includes?("(")
          effective_line = python_paren_delta(line) > 0 ? join_until_python_call_closes(lines, line_index, line) : line
          if static_path = extract_static_route_path(effective_line)
            details = Details.new(PathInfo.new(path, line_index + 1))
            result << Endpoint.new(static_route_path(static_path), "GET", details)
          end
        end
      end

      routes.each do |route_info|
        line_index, route_path, resource_ref, suffix = route_info
        resource_ref = resource_instances[resource_ref]? || resource_ref
        resolved_class = resolve_resource_class(
          resource_ref,
          path,
          source,
          lines,
          classes,
          import_map,
          source_cache,
          class_cache
        )
        next if resolved_class.nil?

        class_path, class_source, class_lines, class_line = resolved_class

        responder_name = suffix.empty? ? nil : suffix
        emit_endpoints_for_class(
          route_file_path: path,
          class_file_path: class_path,
          lines: class_lines,
          class_line: class_line,
          route_path: route_path,
          route_line: line_index,
          suffix: responder_name,
          definition_base_path: definition_base_path,
          source: class_source
        )
      end
    end

    private def emit_endpoints_for_class(*,
                                         route_file_path : ::String,
                                         class_file_path : ::String,
                                         lines : Array(::String),
                                         class_line : Int32,
                                         route_path : ::String,
                                         route_line : Int32,
                                         suffix : ::String?,
                                         definition_base_path : ::String,
                                         source : ::String)
      class_indent = indent_level(lines[class_line])

      i = class_line + 1
      while i < lines.size
        line = lines[i]
        stripped = line.lstrip

        unless stripped.empty? || stripped.starts_with?("#")
          # Stop at any line that is not more indented than the class definition
          # (next class, top-level def, module-level statement, etc.).
          break if indent_level(line) <= class_indent

          if def_match = line.match(/^\s*(?:async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
            method_name = def_match[1]
            http_method = resolve_responder(method_name, suffix)
            if http_method
              codeblock = parse_code_block(lines[i..])
              body_lines = codeblock ? codeblock.split("\n") : [] of ::String
              params = extract_request_params(body_lines, http_method)
              path_params_from_url(route_path).each { |p| params << p }

              details = Details.new(PathInfo.new(route_file_path, route_line + 1))
              endpoint = Endpoint.new(normalize_path(route_path), http_method, params)
              endpoint.details = details

              push_callees_from(
                endpoint,
                codeblock || "",
                i,
                class_file_path,
                definition_base_path: definition_base_path,
                source: source
              )

              result << endpoint
            end
          end
        end

        i += 1
      end
    end

    # Matches a responder method name against an optional `suffix=` filter.
    # Without a suffix, only bare `on_get` / `on_post` / … are accepted.
    # With suffix `item`, only `on_get_item` / `on_post_item` / … match.
    private def resolve_responder(method_name : ::String, suffix : ::String?) : ::String?
      RESPONDER_METHODS.each do |responder, http_method|
        if suffix.nil? || suffix.empty?
          return http_method if method_name == responder
        else
          return http_method if method_name == "#{responder}_#{suffix}"
        end
      end
      nil
    end

    private def resolve_resource_class(resource_ref : ::String,
                                       current_path : ::String,
                                       current_source : ::String,
                                       current_lines : Array(::String),
                                       current_classes : Hash(::String, Int32),
                                       import_map : Hash(::String, Tuple(::String, Int32)),
                                       source_cache : Hash(::String, ::String),
                                       class_cache : Hash(::String, Hash(::String, Int32))) : Tuple(::String, ::String, Array(::String), Int32)?
      parts = resource_ref.split(".")
      return if parts.empty?

      if parts.size == 1
        class_name = parts[0]
        if class_line = current_classes[class_name]?
          return {current_path, current_source, current_lines, class_line}
        end

        if imported = import_map[class_name]?
          return resolve_class_in_file(imported[0], class_name, source_cache, class_cache)
        end

        return
      end

      import_name = parts[0]
      class_name = parts[-1]
      return unless imported = import_map[import_name]?

      resolve_class_in_file(imported[0], class_name, source_cache, class_cache)
    end

    private def resolve_class_in_file(file_path : ::String,
                                      class_name : ::String,
                                      source_cache : Hash(::String, ::String),
                                      class_cache : Hash(::String, Hash(::String, Int32))) : Tuple(::String, ::String, Array(::String), Int32)?
      return if file_path.empty? || !File.exists?(file_path)

      source = source_cache[file_path] ||= read_file_content(file_path)
      lines = source.lines
      classes = class_cache[file_path] ||= collect_classes(lines)
      return unless class_line = classes[class_name]?

      {file_path, source, lines, class_line}
    end

    private def collect_classes(lines : Array(::String)) : Hash(::String, Int32)
      classes = Hash(::String, Int32).new
      lines.each_with_index do |line, line_index|
        if class_match = line.match(/^\s*class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[\(:]/)
          classes[class_match[1]] = line_index
        end
      end
      classes
    end

    private def path_params_from_url(route_path : ::String) : Array(Param)
      params = [] of Param
      route_path.scan(/\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[^}]+)?\}/) do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def extract_static_route_path(line : ::String) : ::String?
      call_match = line.match(/\.add_static_route\s*\((.*)\)\s*$/m)
      return unless call_match

      args = split_python_arguments(call_match[1])
      extract_keyword_string(args, "prefix") || args[0]?.try { |arg| extract_python_string(arg) }
    end

    private def split_python_arguments(args : ::String) : Array(::String)
      parts = [] of ::String
      current = String::Builder.new
      depth = 0
      in_quote : Char? = nil
      escaped = false

      args.each_char do |ch|
        if in_quote
          current << ch
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end

        case ch
        when '\'', '"'
          in_quote = ch
          current << ch
        when '(', '[', '{'
          depth += 1
          current << ch
        when ')', ']', '}'
          depth -= 1 if depth > 0
          current << ch
        when ','
          if depth == 0
            parts << current.to_s
            current = String::Builder.new
          else
            current << ch
          end
        else
          current << ch
        end
      end

      parts << current.to_s
      parts
    end

    # Memoized per keyword — the keyword set is tiny (`prefix`) but this
    # runs per argument of every static-route declaration (an interpolated
    # regex literal recompiles PCRE2 on every evaluation).
    private def keyword_string_regex(keyword : ::String) : Regex
      @keyword_regex_cache[keyword] ||= /^\s*#{Regex.escape(keyword)}\s*=\s*(.+)$/m
    end

    private def extract_keyword_string(args : Array(::String), keyword : ::String) : ::String?
      keyword_re = keyword_string_regex(keyword)
      args.each do |arg|
        keyword_match = arg.match(keyword_re)
        next unless keyword_match

        return extract_python_string(keyword_match[1])
      end

      nil
    end

    private def extract_python_string(expression : ::String) : ::String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
    end

    private def static_route_path(route_path : ::String) : ::String
      normalized = normalize_path(route_path)
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized.gsub(/\/+/, "/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized == "/" ? "/*" : "#{normalized}/*"
    end

    # Strip Falcon type converters from the URL so `/things/{id:int}` is
    # reported as `/things/{id}`, matching how the endpoint is actually
    # invoked by clients.
    private def normalize_path(route_path : ::String) : ::String
      route_path.gsub(/\{([a-zA-Z_][a-zA-Z0-9_]*):[^}]+\}/) do |_match|
        "{#{$~[1]}}"
      end
    end

    # Memoized per media-variable name (`data`, `body`, ...): the patterns
    # interpolate a discovered name so they can't be class constants, but
    # responder bodies reuse the same few names across a whole project.
    private def media_var_regexes(var : ::String) : Tuple(Regex, Regex)
      @media_var_regex_cache[var] ||= begin
        v = Regex.escape(var)
        {/(?:^|[^a-zA-Z0-9_])#{v}\s*\[\s*['"]([^'"]+)['"]\s*\]/,
         /(?:^|[^a-zA-Z0-9_])#{v}\.get\s*\(\s*['"]([^'"]+)['"]/}
      end
    end

    private def extract_request_params(body_lines : Array(::String), http_method : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new
      media_vars = [] of ::String
      media_access_seen = false
      media_field_seen = false
      body_method = http_method != "GET" && http_method != "HEAD" && http_method != "OPTIONS"

      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      body_lines.each do |line|
        line.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:await\s+)?req\.media\b/) do |m|
          media_vars << m[1] unless media_vars.includes?(m[1])
          media_access_seen = true
        end
        line.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*(?:await\s+)?req\.get_media\s*\(/) do |m|
          media_vars << m[1] unless media_vars.includes?(m[1])
          media_access_seen = true
        end
        media_access_seen = true if line.matches?(/req\.media\b/) || line.matches?(/req\.get_media\s*\(/)
      end

      body_lines.each do |line|
        # req.get_param("key"), req.get_param_as_int("key"), etc.
        line.scan(/req\.get_param(?:_as_[a-zA-Z_]+)?\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "query")
        end
        # req.params["key"] / req.params.get("key")
        line.scan(/req\.params\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "query")
        end
        line.scan(/req\.params\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "query")
        end

        # req.get_header("X-Foo")
        line.scan(/req\.get_header\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "header")
        end

        # req.cookies["name"] / req.cookies.get("name")
        line.scan(/req\.cookies\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "cookie")
        end
        line.scan(/req\.cookies\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "cookie")
        end
        line.scan(/req\.get_cookie_values\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "cookie")
        end

        # req.media["name"] / req.media.get("name") and variables assigned
        # from req.media / await req.get_media().
        if body_method
          line.scan(/req\.media\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
            media_field_seen = true
            record.call(m[1], "json")
          end
          line.scan(/req\.media\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
            media_field_seen = true
            record.call(m[1], "json")
          end
          media_vars.each do |var|
            # The var name is a necessary substring for either pattern.
            next unless line.includes?(var)
            bracket_re, get_re = media_var_regexes(var)
            line.scan(bracket_re) do |m|
              media_field_seen = true
              record.call(m[1], "json")
            end
            line.scan(get_re) do |m|
              media_field_seen = true
              record.call(m[1], "json")
            end
          end
        end

        # req.bounded_stream — raw body, treat as form for write methods.
        if line.includes?("req.bounded_stream")
          record.call("body", "form") if body_method
        end
      end

      record.call("body", "json") if body_method && media_access_seen && !media_field_seen

      params
    end

    private def indent_level(line : ::String) : Int32
      line.size - line.lstrip.size
    end
  end
end
