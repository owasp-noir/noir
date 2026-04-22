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

    # Parse key per-file state:
    #   routes[path] = list of {line_index, route_path, class_name, suffix}
    #   classes[path] = { class_name => class_def_line_index }
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String))).new
    @classes = Hash(::String, Hash(::String, Int32)).new

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("falcon"))

            @routes[path] ||= [] of Tuple(Int32, ::String, ::String, ::String)
            @classes[path] ||= Hash(::String, Int32).new

            lines.each_with_index do |line, line_index|
              # Record class definitions for later responder lookup.
              if class_match = line.match(/^\s*class\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*[\(:]/)
                @classes[path][class_match[1]] = line_index
              end

              # `xxx.add_route('/path', ResourceClass(), suffix='item')`
              # Path argument preserves original spacing (we match the raw line).
              if route_match = line.match(/\.add_route\s*\(\s*[rf]?['"]([^'"]*)['"]\s*,\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
                route_path = route_match[1]
                class_name = route_match[2]
                suffix = ""
                if suffix_match = line.match(/suffix\s*=\s*['"]([^'"]*)['"]/)
                  suffix = suffix_match[1]
                end
                @routes[path] << {line_index, route_path, class_name, suffix}
              end
            end
          end
        end
      end

      @routes.each do |path, route_list|
        lines = read_file_lines(path)
        classes_in_file = @classes[path]? || Hash(::String, Int32).new
        route_list.each do |route_info|
          line_index, route_path, class_name, suffix = route_info
          class_line = classes_in_file[class_name]?
          next if class_line.nil?

          responder_name = suffix.empty? ? nil : suffix
          emit_endpoints_for_class(path, lines, class_line, route_path, line_index, responder_name)
        end
      end

      result
    end

    private def emit_endpoints_for_class(path : ::String, lines : Array(::String), class_line : Int32,
                                         route_path : ::String, route_line : Int32, suffix : ::String?)
      class_indent = indent_level(lines[class_line])

      i = class_line + 1
      while i < lines.size
        line = lines[i]
        stripped = line.lstrip

        unless stripped.empty?
          # Stop at the next class at same or lesser indentation.
          if stripped.starts_with?("class ") && indent_level(line) <= class_indent
            break
          end

          if def_match = line.match(/^(\s*)(?:async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/)
            method_indent = def_match[1].size
            # Must be a method of this class, not an outer def.
            if method_indent > class_indent
              method_name = def_match[2]
              http_method = resolve_responder(method_name, suffix)
              if http_method
                codeblock = parse_code_block(lines[i..])
                body_lines = codeblock ? codeblock.split("\n") : [] of ::String
                params = extract_request_params(body_lines, http_method)
                path_params_from_url(route_path).each { |p| params << p }

                details = Details.new(PathInfo.new(path, route_line + 1))
                endpoint = Endpoint.new(normalize_path(route_path), http_method, params)
                endpoint.details = details
                result << endpoint
              end
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

    private def path_params_from_url(route_path : ::String) : Array(Param)
      params = [] of Param
      route_path.scan(/\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[^}]+)?\}/) do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    # Strip Falcon type converters from the URL so `/things/{id:int}` is
    # reported as `/things/{id}`, matching how the endpoint is actually
    # invoked by clients.
    private def normalize_path(route_path : ::String) : ::String
      route_path.gsub(/\{([a-zA-Z_][a-zA-Z0-9_]*):[^}]+\}/) do |_match|
        "{#{$~[1]}}"
      end
    end

    private def extract_request_params(body_lines : Array(::String), http_method : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new

      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
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

        # req.media / await req.get_media() — body (json for write methods).
        if line.matches?(/req\.media\b/) || line.matches?(/req\.get_media\s*\(/)
          if http_method != "GET" && http_method != "HEAD" && http_method != "OPTIONS"
            record.call("body", "json")
          end
        end

        # req.bounded_stream — raw body, treat as form for write methods.
        if line.includes?("req.bounded_stream")
          if http_method != "GET" && http_method != "HEAD" && http_method != "OPTIONS"
            record.call("body", "form")
          end
        end
      end

      params
    end

    private def read_file_lines(path : ::String) : Array(::String)
      content = File.read(path, encoding: "utf-8", invalid: :skip)
      content.split("\n")
    rescue e : IO::Error
      @logger.debug "Failed to read #{path}: #{e.message}"
      [] of ::String
    end

    private def indent_level(line : ::String) : Int32
      line.size - line.lstrip.size
    end
  end
end
