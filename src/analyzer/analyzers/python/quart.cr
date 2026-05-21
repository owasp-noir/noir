require "../../../miniparsers/python"
require "../../../miniparsers/python_route_extractor"
require "../../../miniparsers/python_route_extractor_ts"
require "../../engines/python_engine"

module Analyzer::Python
  # Quart is an ASGI re-implementation of Flask's API. Decorator,
  # Blueprint, and request-object shapes mirror Flask 1:1, so this
  # analyzer leans on the same tree-sitter helpers as the Flask one
  # and adds two Quart-specific pieces:
  #
  #   * `@app.websocket("/ws")` — surfaced as `GET` + `protocol = "ws"`
  #     so the existing endpoint pipeline carries it through unchanged
  #   * `await request.get_json()` / `request.json` body extraction —
  #     the same patterns Flask uses; nothing extra is needed because
  #     parameter extraction reads the function body line-by-line and
  #     the `await` prefix doesn't change the access shape.
  class Quart < PythonEngine
    # Reference: https://quart.palletsprojects.com/en/latest/reference/source/quart.wrappers.request.html
    REQUEST_PARAM_FIELDS = {
      "data"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "args"    => {["GET"], "query"},
      "form"    => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "files"   => {["POST", "PUT", "PATCH", "DELETE"], "form"},
      "values"  => {["GET", "POST", "PUT", "PATCH", "DELETE"], "query"},
      "json"    => {["POST", "PUT", "PATCH", "DELETE"], "json"},
      "cookies" => {nil, "cookie"},
      "headers" => {nil, "header"},
    }

    REQUEST_PARAM_TYPES = {
      "query"  => nil,
      "form"   => ["POST", "PUT", "PATCH", "DELETE"],
      "json"   => ["POST", "PUT", "PATCH", "DELETE"],
      "cookie" => nil,
      "header" => nil,
    }

    # `@app.websocket("/ws")` is the only attribute outside the
    # standard HTTP-method set that the tree-sitter extractor needs
    # to surface here. The synthesised method stays `GET` so the
    # downstream filter logic (which keys off HTTP methods) keeps
    # working; the analyzer rewrites `protocol` to `"ws"` later.
    WEBSOCKET_ATTRIBUTES = {"websocket" => "GET"}

    @file_content_cache = Hash(::String, ::String).new
    @parsers = Hash(::String, PythonParser).new
    @routes = Hash(::String, Array(Tuple(Int32, ::String, ::String, ::String, Bool))).new

    def analyze
      quart_instances = Hash(::String, ::String).new
      quart_instances["app"] ||= "" # Common Quart instance name
      blueprint_prefixes = Hash(::String, ::String).new
      path_api_instances = Hash(::String, Hash(::String, ::String)).new
      register_blueprint = Hash(::String, Hash(::String, ::String)).new

      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")
          next if PythonEngine.python_test_path?(path)
          @logger.debug "Analyzing #{path}"

          file_content = fetch_file_content(path)
          lines = file_content.lines
          next unless lines.any?(&.includes?("quart"))

          api_instances = Hash(::String, ::String).new
          path_api_instances[path] = api_instances
          import_map_cache : Hash(::String, Tuple(::String, Int32))? = nil

          # Tree-sitter pre-pass: harvest every `@<router>.route(...)`,
          # `@<router>.<method>(...)`, and `@<router>.websocket(...)`
          # decorator, plus every `<name> = (quart.)?Blueprint(...)`
          # declaration. One parse per file vs. (lines × patterns) regex
          # work; multi-line decorators come along for free.
          ts_decorations = Noir::TreeSitterPythonRouteExtractor.extract_decorations(file_content, nil, WEBSOCKET_ATTRIBUTES)
          ts_decorations.each do |decoration|
            is_ws = decoration.attribute_name == "websocket"
            methods_literal = decoration.methods.map { |m| "'#{m}'" }.join(",")
            extra_params = "methods=[#{methods_literal}]"
            router_info = Tuple(Int32, ::String, ::String, ::String, Bool).new(
              decoration.decorator_line, path, decoration.path, extra_params, is_ws
            )
            @routes[decoration.router_name] ||= [] of Tuple(Int32, ::String, ::String, ::String, Bool)
            @routes[decoration.router_name] << router_info
          end

          Noir::TreeSitterPythonRouteExtractor.extract_blueprints(file_content, ["quart"]).each do |bp|
            blueprint_prefixes[bp.name] ||= bp.prefix
            api_instances[bp.name] ||= bp.prefix
          end

          lines.each_with_index do |original_line, line_index|
            line = original_line.gsub(" ", "")

            # Identify Quart instance assignments: `app = Quart(__name__)`
            quart_match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:quart\.)?Quart\(/
            if quart_match
              quart_instance_name = quart_match[1]
              api_instances[quart_instance_name] ||= ""
              quart_instances[quart_instance_name] ||= ""
            end

            # Identify Blueprint registration:
            #   `app.register_blueprint(bp, url_prefix="/api")`
            register_blueprint_match = line.match /(#{PYTHON_VAR_NAME_REGEX})\.register_blueprint\((#{DOT_NATION})/
            if register_blueprint_match
              url_prefix_match = original_line.match /url_prefix\s*=\s*[rf]?['"]([^'"]*)['"]/
              if url_prefix_match
                blueprint_name = register_blueprint_match[2]
                resolved = false
                parser = get_parser(path)
                if parser.@global_variables.has_key?(blueprint_name)
                  gv = parser.@global_variables[blueprint_name]
                  if gv.type == "Blueprint"
                    register_blueprint[gv.path] ||= Hash(::String, ::String).new
                    register_blueprint[gv.path][blueprint_name] = url_prefix_match[1]
                    resolved = true
                  end
                end

                unless resolved
                  import_map_cache ||= find_imported_modules(current_base_path, path)
                  if import_map_cache.has_key?(blueprint_name)
                    source_file, _package_type = import_map_cache[blueprint_name]
                    if !source_file.empty? && File.exists?(source_file)
                      register_blueprint[source_file] ||= Hash(::String, ::String).new
                      register_blueprint[source_file][blueprint_name] = url_prefix_match[1]
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Resolve url_prefix discovered at register_blueprint sites back to
      # the file that declared the Blueprint.
      register_blueprint.each do |path, blueprint_info|
        blueprint_info.each do |blueprint_name, blueprint_prefix|
          if path_api_instances.has_key?(path)
            api_instances = path_api_instances[path]
            if api_instances.has_key?(blueprint_name)
              api_instances[blueprint_name] = File.join(blueprint_prefix, api_instances[blueprint_name])
            end
          end
        end
      end

      # Iterate through the collected route decorations and extract endpoints
      @routes.each do |router_name, router_info_list|
        router_info_list.each do |router_info|
          line_index, path, route_path, extra_params, is_ws = router_info
          source = fetch_file_content(path)
          lines = source.lines
          api_instances = path_api_instances[path]?
          prefix = (api_instances && api_instances.has_key?(router_name)) ? api_instances[router_name] : ""

          class_def_index = Noir::PythonRouteExtractor.find_def_line(lines, line_index, :down)
          next if class_def_index >= lines.size
          next unless lines[class_def_index].lstrip.starts_with?("def ") ||
                     lines[class_def_index].lstrip.starts_with?("async def ")

          def_match = lines[class_def_index].match /(\s*)(async\s+)?def\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(/
          next unless def_match
          function_name = def_match[3]

          codeblock = parse_code_block(lines[class_def_index..])
          next if codeblock.nil?
          codeblock_lines = codeblock.split("\n")

          handler_callees = build_callees_from(
            codeblock,
            class_def_index,
            path,
            definition_base_path: base_path_for(path),
            source: source,
          )

          if is_ws
            # `@app.websocket("/ws")` always emits a single WS endpoint;
            # methods array is forced to GET upstream so the filter
            # plumbing doesn't drop it. Skip param extraction — Quart
            # WebSocket handlers don't read `request.<field>`.
            route_url = "#{prefix}#{route_path}"
            route_url = "/#{route_url}" unless route_url.starts_with?("/")
            details = Details.new(PathInfo.new(path, line_index + 1))
            endpoint = Endpoint.new(route_url.gsub("//", "/"), "GET", details)
            endpoint.protocol = "ws"
            handler_callees.each { |c| endpoint.push_callee(c) }
            result << endpoint
            next
          end

          default_method = HTTP_METHODS.find { |http_method| function_name.downcase == http_method.downcase } || "GET"
          get_endpoints(default_method, route_path, extra_params, codeblock_lines, prefix).each do |endpoint|
            endpoint.details = Details.new(PathInfo.new(path, line_index + 1))
            handler_callees.each { |c| endpoint.push_callee(c) }
            result << endpoint
          end
        end
      end

      Fiber.yield
      result
    end

    private def fetch_file_content(path : ::String) : ::String
      @file_content_cache[path] ||= read_file_content(path)
    end

    private def base_path_for(file_path : ::String) : ::String
      base_paths.find { |bp| file_path.starts_with?(bp) } || base_paths[0]? || ""
    end

    def create_parser(path : ::String, content : ::String = "") : PythonParser
      content = fetch_file_content(path) if content.empty?
      PythonParser.new(path, content, @parsers, depth: 0)
    end

    def get_parser(path : ::String, content : ::String = "") : PythonParser
      @parsers[path] ||= create_parser(path, content)
      @parsers[path]
    end

    # Build endpoints from a single route decoration. Mirrors the Flask
    # adapter's behaviour: split on declared `methods=[...]`, default to
    # GET, run parameter extraction over the handler body once and
    # filter the params per method.
    def get_endpoints(method : ::String, route_path : ::String, extra_params : ::String,
                      codeblock_lines : Array(::String), prefix : ::String)
      endpoints = [] of Endpoint
      methods = [] of ::String

      if !prefix.ends_with?("/") && !route_path.starts_with?("/")
        prefix = "#{prefix}/"
      end

      methods_match = extra_params.match /methods\s*=\s*(.*)/
      if !methods_match.nil? && methods_match.size == 2
        methods_match[1].scan(/['"]([^'"]*)['"']/) do |m|
          method_name = m[1].upcase
          methods << method_name if HTTP_METHODS.any? { |hm| hm.upcase == method_name }
        end
      end
      methods << method.upcase if methods.empty?

      suspicious_params = extract_request_params(codeblock_lines)

      methods.uniq.each do |http_method_name|
        route_url = "#{prefix}#{route_path}"
        route_url = "/#{route_url}" unless route_url.starts_with?("/")

        params = get_filtered_params(http_method_name, suspicious_params)
        endpoints << Endpoint.new(route_url.gsub("//", "/"), http_method_name, params)
      end

      endpoints
    end

    # Scans a handler body for `request.<field>` access patterns and
    # `data = await request.get_json()` / `data = request.json`
    # assignments, then emits a `Param` per discovered key. The
    # `await` keyword is invisible to the access shape so the same
    # regexes work for sync Flask and async Quart.
    private def extract_request_params(codeblock_lines : Array(::String)) : Array(Param)
      params = [] of Param
      json_variable_names = [] of ::String

      codeblock_lines.each do |codeblock_line|
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*(?:await\s+)?json\.loads\((?:await\s+)?request\.data/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
        match = codeblock_line.match /([a-zA-Z_][a-zA-Z0-9_]*).*=\s*(?:await\s+)?request\.(?:get_json\([^)]*\)|json)/
        if !match.nil? && match.size == 2 && !json_variable_names.includes?(match[1])
          json_variable_names << match[1]
        end
      end

      codeblock_lines.each do |codeblock_line|
        REQUEST_PARAM_FIELDS.each do |field_name, tuple|
          _, noir_param_type = tuple
          matches = codeblock_line.scan(/request\.#{field_name}\[[rf]?['"]([^'"]*)['"]\]/)
          if matches.size == 0
            matches = codeblock_line.scan(/request\.#{field_name}\.get\([rf]?['"]([^'"]*)['"]/)
          end
          if matches.size == 0
            noir_param_type = "json"
            json_variable_names.each do |json_variable_name|
              matches = codeblock_line.scan(/[^a-zA-Z_]#{json_variable_name}\[[rf]?['"]([^'"]*)['"]\]/)
              if matches.size == 0
                matches = codeblock_line.scan(/[^a-zA-Z_]#{json_variable_name}\.get\([rf]?['"]([^'"]*)['"]/)
              end
              break if matches.size > 0
            end
          end

          matches.each do |parameter_match|
            next if parameter_match.size != 2
            params << Param.new(parameter_match[1], "", noir_param_type)
          end
        end
      end

      params
    end

    def get_filtered_params(method : ::String, params : Array(Param)) : Array(Param)
      filtered_params = Array(Param).new
      upper_method = method.upcase

      params.each do |param|
        is_support_param = false
        support_methods = REQUEST_PARAM_TYPES.fetch(param.param_type, nil)
        if !support_methods.nil?
          support_methods.each do |support_method|
            is_support_param = true if upper_method == support_method.upcase
          end
        else
          is_support_param = true
        end

        filtered_params.each do |filtered_param|
          if filtered_param.name == param.name && filtered_param.param_type == param.param_type
            is_support_param = false
            break
          end
        end

        filtered_params << param if is_support_param
      end

      filtered_params
    end
  end
end
