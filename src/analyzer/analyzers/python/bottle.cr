require "../../../miniparsers/python_route_extractor"
require "../../engines/python_engine"

module Analyzer::Python
  class Bottle < PythonEngine
    # Reference: https://bottlepy.org/docs/dev/tutorial.html#request-routing
    #
    # Bottle supports two decorator forms:
    #
    #   1. Instance-bound: `@app.route("/path")` / `@app.get("/path")` / …
    #      Same shape as Flask/Sanic, handled by PythonRouteExtractor.
    #
    #   2. Bare (module-level default app): `@route("/path")` / `@get("/path")` / …
    #      Unique to Bottle-style micro frameworks — `from bottle import route, get`
    #      then decorate a function directly.
    #
    # For parameter extraction, Bottle exposes attributes on `request`:
    #   request.query.<name> / .get("name") / ["name"]       → query
    #   request.forms.<name> / .get("name") / ["name"]       → form
    #   request.json.get("name") / ["name"]                  → json
    #   request.headers.get("X-Foo") / ["X-Foo"]             → header
    #   request.get_cookie("name") / request.cookies.get(...) → cookie
    #
    # Path parameters use `<name>` or `<name:filter>` in the route string
    # and are preserved as-is in endpoint URLs (matching Flask's convention
    # — that's what fixture specs assert against).

    BARE_DECORATORS = %w[route get post put delete patch head options]

    def analyze
      # Pulls from the detector-built file_map so subtree pruning and
      # --exclude-path apply to this pass too.
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(prefix) || path == current_base_path
          next if path.includes?("/site-packages/")
          @logger.debug "Analyzing #{path}"

          File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
            lines = file.each_line.to_a
            next unless lines.any?(&.includes?("bottle"))

            lines.each_with_index do |line, line_index|
              stripped = line.gsub(" ", "")

              # Form 1: @<var>.route / @<var>.<method>
              Noir::PythonRouteExtractor.scan_decorators(stripped, line).each do |deco|
                process_route(path, lines, line_index, deco.path, deco.extra_params)
              end

              # Form 2: bare @route("/path") / @<method>("/path")
              BARE_DECORATORS.each do |deco_name|
                # `@route("/foo", method="POST")` or `@get("/foo")` on the stripped line.
                if bare_match = stripped.match(/^@#{deco_name}\([rf]?['"]([^'"]*)['"](.*)/)
                  # Recover spaces in path via the original line.
                  path_value = bare_match[1]
                  if orig_match = line.match(/@#{deco_name}\s*\(\s*[rf]?['"]([^'"]*)['"]/)
                    path_value = orig_match[1]
                  end
                  extra = deco_name == "route" ? bare_match[2] : "methods=['#{deco_name.upcase}']"
                  process_route(path, lines, line_index, path_value, extra)
                end
              end
            end
          end
        end
      end

      result
    end

    # Turn an (extra_params) string from a decorator into the list of HTTP
    # methods it applies to. Handles `method="POST"`, `method='POST'`,
    # `methods=["GET", "POST"]`, and the extractor-synthesized
    # `methods=['POST']` form.
    private def extract_methods(extra_params : String) : Array(String)
      methods = [] of String

      # Bottle accepts both `method="POST"` and `method=['POST']`, and the
      # PythonRouteExtractor also synthesizes `methods=['GET']` for
      # @<var>.<method> decorators — hence `methods?` covers both singular
      # and plural.
      if m = extra_params.match(/methods?\s*=\s*['"]([A-Za-z]+)['"]/)
        methods << m[1].upcase
      end

      if m = extra_params.match(/methods?\s*=\s*[\[\(]([^\]\)]+)[\]\)]/)
        m[1].scan(/['"]([A-Za-z]+)['"]/) do |method_match|
          methods << method_match[1].upcase
        end
      end

      methods.uniq
    end

    private def process_route(path : String, lines : Array(String), line_index : Int32, route_path : String, extra_params : String)
      methods = extract_methods(extra_params)
      methods = ["GET"] if methods.empty?

      def_index = Noir::PythonRouteExtractor.find_def_line(lines, line_index)
      return if def_index == line_index

      function_body = extract_function_body(lines, def_index)

      request_params = extract_request_params(function_body)

      # Preserve path parameters from `<name>` or `<name:filter>` syntax as path params.
      path_params = [] of Param
      route_path.scan(/<(\w+)(?::[^>]+)?>/) do |match|
        path_params << Param.new(match[1], "", "path")
      end

      details = Details.new(PathInfo.new(path, line_index + 1))
      methods.each do |method|
        endpoint = Endpoint.new(route_path, method, details)
        path_params.each { |p| endpoint.push_param(p) }
        request_params.each { |p| endpoint.push_param(p) }
        result << endpoint
      end
    end

    # Walk forward from `def_index` collecting lines at strictly greater
    # indentation than the def line — that's the function body.
    private def extract_function_body(lines : Array(String), def_index : Int32) : String
      return "" if def_index >= lines.size
      def_line = lines[def_index]
      base_indent = def_line.size - def_line.lstrip.size

      body = [] of String
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

    # Bottle attributes whose parameter type is independent of HTTP method.
    # Maps the Python accessor name on `request.<name>` to the noir param_type.
    DICT_ACCESSORS = {
      "query"   => "query",
      "forms"   => "form",
      "json"    => "json",
      "headers" => "header",
      "cookies" => "cookie",
    }

    # Attribute names on accessor objects that are not user parameters.
    DICT_METHOD_NAMES = Set{"get", "getall", "getone", "items", "keys", "values", "pop"}

    # Scan a function body for Bottle's request accessors.
    # Bottle uses explicit accessor names (`request.forms` for form,
    # `request.json` for json, …) so method-based disambiguation isn't needed.
    private def extract_request_params(body : String) : Array(Param)
      params = [] of Param
      seen = Set(String).new

      record = ->(name : String, type : String) do
        key = "#{type}:#{name}"
        unless seen.includes?(key)
          params << Param.new(name, "", type)
          seen << key
        end
      end

      DICT_ACCESSORS.each do |accessor, param_type|
        # request.<accessor>.get("name")
        body.scan(/request\.#{accessor}\.get\s*\(\s*['"]([^'"]+)['"]/) do |m|
          record.call(m[1], param_type)
        end
        # request.<accessor>["name"]
        body.scan(/request\.#{accessor}\s*\[\s*['"]([^'"]+)['"]\s*\]/) do |m|
          record.call(m[1], param_type)
        end
        # request.<accessor>.<attribute>  — skip dict-API method names.
        body.scan(/request\.#{accessor}\.([A-Za-z_][A-Za-z0-9_]*)\b/) do |m|
          next if DICT_METHOD_NAMES.includes?(m[1])
          record.call(m[1], param_type)
        end
      end

      # Bottle-specific cookie helper.
      body.scan(/request\.get_cookie\s*\(\s*['"]([^'"]+)['"]/) do |m|
        record.call(m[1], "cookie")
      end

      params
    end
  end
end
