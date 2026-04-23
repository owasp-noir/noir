require "../../../miniparsers/python_route_extractor"
require "../../engines/python_engine"

module Analyzer::Python
  class Aiohttp < PythonEngine
    # Reference: https://docs.aiohttp.org/en/stable/web_quickstart.html
    #
    # aiohttp supports two route registration styles:
    #
    #   1. Imperative: `app.router.add_get("/path", handler)`,
    #      `app.router.add_route("GET", "/path", handler)`, etc.
    #
    #   2. RouteTableDef decorators: `@routes.get("/path")`,
    #      `@routes.route("GET", "/path")`, etc. (shape is the same as
    #      Flask/Sanic and handled by PythonRouteExtractor.)
    #
    # Handlers receive a `request` object with attributes for reading
    # inputs:
    #   request.match_info["name"] / .get("name")            → path
    #   request.rel_url.query["x"] / request.query["x"]      → query
    #   request.headers["X-Foo"] / .get("X-Foo")             → header
    #   request.cookies["sid"] / .get("sid")                 → cookie
    #   await request.json()  (optionally assigned to a var) → json
    #   await request.post()  (optionally assigned to a var) → form
    #
    # Path parameters use `{name}` in the route string and are recorded
    # as `path` params, matching Bottle / FastAPI conventions.

    HTTP_METHOD_NAMES = %w[get post put delete patch head options]

    def analyze
      handler_routes = Hash(::String, Array(Tuple(::String, ::String, Int32, ::String))).new
      # path => [{route_path, http_method, line_index, handler_name}]

      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("aiohttp"))

            handler_routes[path] ||= [] of Tuple(::String, ::String, Int32, ::String)

            lines.each_with_index do |line, line_index|
              stripped = line.gsub(" ", "")

              # Style B: @routes.route("GET", "/path") — first arg is the method, second is the path.
              # aiohttp's .route() signature differs from Flask/Sanic, so handle it explicitly
              # and skip the generic extractor for this decorator shape.
              aiohttp_route_deco = stripped.match(/@(#{PYTHON_VAR_NAME_REGEX})\.route\([rf]?['"]([A-Za-z*]+)['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
              if aiohttp_route_deco
                method = aiohttp_route_deco[2].upcase
                route_path = aiohttp_route_deco[3]
                if orig_match = line.match(/@#{aiohttp_route_deco[1]}\s*\.\s*route\s*\(\s*[rf]?['"][A-Za-z*]+['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                process_decorator_route(path, lines, line_index, route_path, method)
              else
                # Style B: @routes.get("/path") / @routes.post("/path") etc.
                Noir::PythonRouteExtractor.scan_decorators(stripped, line).each do |deco|
                  methods = extract_methods(deco.extra_params)
                  methods << "GET" if methods.empty?
                  methods.uniq.each do |deco_method|
                    process_decorator_route(path, lines, line_index, deco.path, deco_method)
                  end
                end
              end

              # Style A: app.router.add_<method>("/path", handler)
              methods_re = HTTP_METHOD_NAMES.join("|")
              if add_match = stripped.match(/\.add_(#{methods_re})\([rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/)
                method_name = add_match[1]
                route_path = add_match[2]
                handler_name = add_match[3]
                if orig_match = line.match(/\.add_#{method_name}\s*\(\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                handler_routes[path] << {route_path, method_name.upcase, line_index, handler_name}
              end

              # Style A: app.router.add_route("METHOD", "/path", handler)
              add_route_match = stripped.match(/\.add_route\([rf]?['"]([A-Za-z*]+)['"]\s*,\s*[rf]?['"]([^'"]*)['"]\s*,\s*(?:handler\s*=\s*)?(#{DOT_NATION})/)
              if add_route_match
                method = add_route_match[1].upcase
                route_path = add_route_match[2]
                handler_name = add_route_match[3]
                if orig_match = line.match(/\.add_route\s*\(\s*[rf]?['"][A-Za-z*]+['"]\s*,\s*[rf]?['"]([^'"]*)['"]/)
                  route_path = orig_match[1]
                end
                handler_routes[path] << {route_path, method, line_index, handler_name}
              end
            end

            # Resolve add_X handler references by finding their def lines.
            handler_routes[path].each do |route_path, method, line_index, handler_name|
              def_index = find_handler_def(lines, handler_name)
              next if def_index.nil?
              emit_endpoint(path, lines, def_index, route_path, method, line_index)
            end
          end
        end
      end

      result
    end

    private def process_decorator_route(path : ::String, lines : Array(::String), line_index : Int32, route_path : ::String, method : ::String)
      def_index = Noir::PythonRouteExtractor.find_def_line(lines, line_index)
      return if def_index == line_index
      emit_endpoint(path, lines, def_index, route_path, method, line_index)
    end

    private def emit_endpoint(path : ::String, lines : Array(::String), def_index : Int32, route_path : ::String, method : ::String, report_line : Int32)
      function_body = extract_function_body(lines, def_index)
      request_params = extract_request_params(function_body, method)

      seen = Set(::String).new
      all_params = [] of Param

      route_path.scan(/\{(\w+)(?::[^}]+)?\}/) do |match|
        key = "path:#{match[1]}"
        unless seen.includes?(key)
          all_params << Param.new(match[1], "", "path")
          seen << key
        end
      end

      request_params.each do |p|
        key = "#{p.param_type}:#{p.name}"
        unless seen.includes?(key)
          all_params << p
          seen << key
        end
      end

      details = Details.new(PathInfo.new(path, report_line + 1))
      endpoint = Endpoint.new(route_path, method, details)
      all_params.each { |p| endpoint.push_param(p) }
      result << endpoint
    end

    private def find_handler_def(lines : Array(::String), handler_name : ::String) : Int32?
      handler_name = handler_name.split(".").last
      lines.each_with_index do |line, idx|
        if line.match(/^\s*(async\s+)?def\s+#{handler_name}\s*\(/)
          return idx
        end
      end
      nil
    end

    private def extract_function_body(lines : Array(::String), def_index : Int32) : ::String
      return "" if def_index >= lines.size
      def_line = lines[def_index]
      base_indent = def_line.size - def_line.lstrip.size

      body = [] of ::String
      i = def_index + 1
      while i < lines.size
        line = lines[i]
        if line.strip.empty?
          body << line
          i += 1
          next
        end
        current_indent = line.size - line.lstrip.size
        break if current_indent <= base_indent
        body << line
        i += 1
      end
      body.join("\n")
    end

    private def extract_methods(extra_params : ::String) : Array(::String)
      methods = [] of ::String
      if m = extra_params.match(/methods?\s*=\s*[\[\(]([^\]\)]+)[\]\)]/)
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
          methods << method_match[1].upcase
        end
      end
      methods.uniq
    end

    DICT_ACCESSORS = {
      "headers" => "header",
      "cookies" => "cookie",
    }

    DICT_METHOD_NAMES = Set{"get", "getall", "getone", "items", "keys", "values", "pop"}

    private def extract_request_params(body : ::String, method : ::String) : Array(Param)
      params = [] of Param
      seen = Set(::String).new

      record = ->(name : ::String, type : ::String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      # request.match_info["name"] / .get("name") — path parameter access
      body.scan(/request\.match_info\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "path")
      end
      body.scan(/request\.match_info\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "path")
      end

      # request.query["x"] / request.query.get("x") / request.rel_url.query[...]
      body.scan(/request\.(?:rel_url\.)?query\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
        record.call(m[1], "query")
      end
      body.scan(/request\.(?:rel_url\.)?query\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "query")
      end

      DICT_ACCESSORS.each do |accessor, param_type|
        body.scan(/request\.#{accessor}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], param_type)
        end
        body.scan(/request\.#{accessor}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], param_type)
        end
      end

      # JSON body: await request.json() and subsequent dict access on the returned var.
      json_vars = [] of ::String
      body.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+request\.json\s*\(/) do |m|
        json_vars << m[1]
      end

      # If request.json() is awaited at all, flag the body with a generic entry.
      if body.match(/await\s+request\.json\s*\(/)
        record.call("body", "json") if json_vars.empty?
      end

      json_vars.each do |var|
        body.scan(/[^a-zA-Z_]#{var}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "json")
        end
        body.scan(/[^a-zA-Z_]#{var}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "json")
        end
      end

      # Form body: await request.post()
      form_vars = [] of ::String
      body.scan(/([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*await\s+request\.post\s*\(/) do |m|
        form_vars << m[1]
      end

      if body.match(/await\s+request\.post\s*\(/)
        record.call("body", "form") if form_vars.empty?
      end

      form_vars.each do |var|
        body.scan(/[^a-zA-Z_]#{var}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], "form")
        end
        body.scan(/[^a-zA-Z_]#{var}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], "form")
        end
      end

      params
    end
  end
end
