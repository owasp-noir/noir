require "../../engines/python_engine"

module Analyzer::Python
  class FastAPI < PythonEngine
    @fastapi_base_path : ::String = ""

    def analyze
      include_router_map = Hash(::String, Hash(::String, Router)).new
      fastapi_base_file : ::String = ""

      begin
        # Iterate through all Python files in all base paths. Pulls from
        # the detector-built file_map so subtree pruning and
        # --exclude-path apply to this pass too.
        python_files = get_files_by_extension(".py")
        base_paths.each do |current_base_path|
          base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
          python_files.each do |path|
            next unless path.starts_with?(base_dir_prefix) || path == current_base_path
            next if path.includes?("/site-packages/")
            next if PythonEngine.python_test_path?(path)
            source = read_file_content(path)

            import_modules = find_imported_modules(current_base_path, path, source)
            codelines = source.split("\n")
            codelines.each_with_index do |original_line, index|
              effective_line = coalesce_constructor_call(codelines, index, original_line, "APIRouter")
              line = effective_line.gsub(" ", "")
              match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:fastapi\.)?FastAPI\(/
              if !match.nil?
                fastapi_instance_name = match[1]
                unless include_router_map.has_key?(fastapi_instance_name)
                  if include_router_map.has_key?(path)
                    include_router_map[path][fastapi_instance_name] ||= Router.new("")
                  else
                    include_router_map[path] = {fastapi_instance_name => Router.new("")}
                  end

                  # base path
                  fastapi_base_file = path
                  @fastapi_base_path = Path.new(File.dirname(path)).parent.to_s
                  # Don't `break` — a single file can declare both
                  # `app = FastAPI()` and one or more
                  # `router = APIRouter(prefix="/api")` instances,
                  # and the APIRouter detection further down must
                  # still run on the remaining lines.
                end
              end

              # https://fastapi.tiangolo.com/tutorial/bigger-applications/
              match = line.match /(#{PYTHON_VAR_NAME_REGEX})(?::#{PYTHON_VAR_NAME_REGEX})?=(?:fastapi\.)?APIRouter\(/
              if !match.nil?
                prefix = ""
                router_instance_name = match[1]
                if param_codes = effective_line.split("APIRouter", 2)[1]?
                  if raw_prefix = extract_python_keyword_expression(param_codes, "prefix")
                    prefix = resolve_string_expression(raw_prefix, source, import_modules) || ""
                  end
                end

                if include_router_map.has_key?(path)
                  include_router_map[path][router_instance_name] = Router.new(prefix)
                else
                  include_router_map[path] = {router_instance_name => Router.new(prefix)}
                end
              end
            end
          end
        end
      rescue e : Exception
        logger.debug e.message
      end

      begin
        configure_router_prefix(fastapi_base_file, include_router_map)

        include_router_map.each do |path, router_map|
          source = read_file_content(path)
          definition_base_path = base_paths.find { |base_path| path.starts_with?(base_path) } || @fastapi_base_path
          import_modules = find_imported_modules(@fastapi_base_path, path, source)
          codelines = source.split("\n")
          router_map.each do |instance_name, router_class|
            codelines.each_with_index do |line, index|
              # FastAPI route decorators routinely span multiple
              # lines:
              #
              #   @app.post(
              #     "/items",
              #     response_model=Item,
              #     tags=["items"],
              #   )
              #
              # Join continuation lines onto the decorator line so the
              # single-line regex below sees the full call shape. The
              # `index` still points at the original decorator line so
              # `find_def_line` / `parse_function_def` / `code_paths`
              # stay aligned with the source.
              effective_line = coalesce_decorator_call(codelines, index, line, instance_name)

              # Some FastAPI declarations pass the path via the
              # `path=` keyword argument (`@app.get(path="/foo")`).
              # Rewrite the call to put the path as the first
              # positional argument so the downstream regex matches.
              effective_line = lift_path_keyword(effective_line, instance_name)

              effective_line.scan(/@#{instance_name}\.([a-zA-Z_]+)\s*\(\s*[rf]?['"]([^'"]*)['"](.*)/) do |match|
                if match.size > 0
                  http_method_name = match[1].downcase
                  if http_method_name.in?(%w[websocket route api_route])
                    http_method_name = "GET"
                  elsif !HTTP_METHODS.includes?(http_method_name)
                    next
                  end

                  http_method_name = http_method_name.upcase

                  http_route_path = match[2]
                  _extra_params = match[3]
                  params = [] of Param

                  # Get path params from route path
                  query_params = [] of ::String
                  http_route_path.scan(/\{(#{PYTHON_VAR_NAME_REGEX})\}/) do |route_match|
                    if route_match.size > 0
                      query_params << route_match[1]
                    end
                  end

                  # Resolve the actual `def` line, skipping stacked
                  # decorators / comments / blank lines between the
                  # route decorator and the handler. Both param
                  # extraction and callee extraction below need this
                  # to be accurate; the previous `index + 1` shortcut
                  # silently misfired on `@app.post(...)` + `@auth_required`
                  # style stacks.
                  def_line = find_def_line(codelines, index) || (index + 1)

                  # Parsing extra params
                  function_definition = parse_function_def(codelines, def_line)
                  if !function_definition.nil?
                    function_params = function_definition.params
                    if function_params.size > 0
                      function_params.each do |param|
                        # https://fastapi.tiangolo.com/tutorial/path-params-numeric-validations/#order-the-parameters-as-you-need-tricks
                        next if param.name == "*"

                        unless query_params.includes?(param.name)
                          # Default value is numeric or string only
                          default_value = return_literal_value(param.default)

                          # Get param type by default value first
                          param_type = infer_parameter_type(param.default) unless param.default.empty?

                          # Get param type by type if not found
                          if param_type.nil? && !param.type.empty?
                            param_type = param.type
                            # https://peps.python.org/pep-0593/
                            param_type = param_type.split("Annotated[", 2)[-1].split(",", 2)[-1] if param_type.includes?("Annotated[")

                            # https://peps.python.org/pep-0484/#union-types
                            param_type = param_type.split("Union[", 2)[-1] if param_type.includes?("Union[")

                            param_type = infer_parameter_type(param_type, true)
                            param_type = "query" if param_type.nil? && param.type.empty?
                          else
                            param_type = "query" if param_type.nil?
                          end

                          if param_type.nil?
                            if /^#{PYTHON_VAR_NAME_REGEX}$/.match(param.type)
                              if param.type.in?(%w[Request dict])
                                function_codeblock = parse_code_block(codelines[def_line..])
                                next if function_codeblock.nil?
                                new_params = find_dictionary_params(function_codeblock, param)
                              elsif import_modules.has_key?(param.type)
                                # Parse model class from module path
                                import_module_path = import_modules[param.type].first

                                # Skip if import module path is not identified
                                next if import_module_path.empty?

                                import_module_source = read_file_content(import_module_path)
                                new_params = find_base_model_params(import_module_source, param.type, param.name)
                              else
                                # Parse model class from current source
                                new_params = find_base_model_params(source, param.type, param.name)
                              end

                              next if new_params.nil?

                              new_params.each do |model_param|
                                params << model_param
                              end
                            end
                          else
                            # Add endpoint param
                            params << Param.new(param.name, default_value, param_type)
                          end
                        end
                      end
                    end
                  end

                  # Honor `methods=[...]` on `@router.route(...)` /
                  # `@router.api_route(...)` decorators by emitting
                  # one endpoint per declared method. Without this
                  # the decorator's method-list was discarded and a
                  # single GET endpoint was produced for what may be
                  # a multi-verb handler.
                  declared_methods = extract_declared_methods(_extra_params)
                  emit_methods = declared_methods.empty? ? [http_method_name] : declared_methods

                  details = Details.new(PathInfo.new(path, index + 1))
                  full_path = router_class.join(http_route_path)
                  base_endpoint = Endpoint.new(full_path, emit_methods.first, params, details)

                  # `parse_code_block(codelines[def_line..])` keeps the
                  # def line, so body row 0 lives at file line `def_line`.
                  handler_codeblock = parse_code_block(codelines[def_line..])
                  if handler_codeblock
                    push_callees_from(
                      base_endpoint,
                      handler_codeblock,
                      def_line,
                      path,
                      definition_base_path: definition_base_path,
                      source: source
                    )
                  end

                  emit_methods.each do |method|
                    endpoint_to_add = if method == emit_methods.first
                                        base_endpoint
                                      else
                                        Endpoint.new(full_path, method, params, details).tap do |dup_ep|
                                          base_endpoint.callees.each { |c| dup_ep.push_callee(c) }
                                        end
                                      end
                    result << endpoint_to_add
                  end
                end
              end

              # Programmatic registration:
              # `app.add_api_route("/x", get_handler, methods=["GET"])`
              # / `app.add_api_websocket_route(...)`. Coalesce the
              # call's continuation lines (same way as the decorator
              # form above), parse path + methods, and emit endpoints
              # without trying to find a handler def — the handler is
              # passed by reference as the 2nd positional argument.
              prog_line = coalesce_programmatic_call(codelines, index, line, instance_name)
              prog_line.scan(/\b#{instance_name}\.(add_api_route|add_api_websocket_route)\s*\(\s*[rf]?['"]([^'"]*)['"](.*)/) do |prog_match|
                next if prog_match.size < 4
                prog_attr = prog_match[1]
                prog_path = prog_match[2]
                prog_tail = prog_match[3]
                prog_methods = extract_declared_methods(prog_tail)
                if prog_methods.empty?
                  prog_methods = prog_attr.includes?("websocket") ? ["GET"] : ["GET"]
                end
                prog_full = router_class.join(prog_path)
                prog_details = Details.new(PathInfo.new(path, index + 1))
                prog_methods.each do |m|
                  result << Endpoint.new(prog_full, m, [] of Param, prog_details)
                end
              end
            end
          end
        rescue e : Exception
          logger.debug e.message
        end
      end
      Fiber.yield

      result
    end

    # Concatenate two URL-prefix segments, normalising the
    # boundary so `combine_router_prefixes("/api/v1", "/users")`
    # gives `/api/v1/users` and `combine_router_prefixes("",
    # "/users")` gives `/users`. Trailing slashes are dropped on
    # the parent so we don't end up with `/api/v1//users`.
    private def combine_router_prefixes(parent : ::String, own : ::String) : ::String
      return own if parent.empty?
      return parent if own.empty?
      normalized_parent = parent.ends_with?("/") ? parent[0..-2] : parent
      if own.starts_with?("/")
        "#{normalized_parent}#{own}"
      else
        "#{normalized_parent}/#{own}"
      end
    end

    # Configures the prefix for each router
    def configure_router_prefix(file : ::String, include_router_map : Hash(::String, Hash(::String, Router)), router_prefix : ::String = "")
      return if file.empty? || !File.exists?(file)

      # Parse the source file for router configuration
      source = read_file_content(file)
      import_modules = find_imported_modules(@fastapi_base_path, file, source)
      include_router_map[file].each do |instance_name, router_class|
        # PREPEND the inherited prefix to the router's own. The
        # initial pass captures `APIRouter(prefix="/users")`, so
        # `router_class.prefix` may already be `/users`; if we
        # overwrite it here with `router_prefix`, the constructor
        # prefix is silently dropped and routes inside the router
        # collapse to the parent's prefix only. Regression on
        # full-stack-fastapi-template: `users.router` and
        # `items.router` both declare `prefix=...` at construction
        # time, but their routes were surfacing without the
        # `/users` / `/items` segment.
        router_class.prefix = combine_router_prefixes(router_prefix, router_class.prefix)

        # Parse '{app}.include_router({item}.router, prefix="{prefix}")' code
        source.scan(/#{instance_name}\.include_router\(([^\)]*)\)/).each do |match|
          if match.size > 0
            params = match[1].split(",")
            prefix = ""
            router_instance_name = params[0].strip
            if params.size != 1
              select_params = params.select(&.strip.starts_with?("prefix"))
              if select_params.size != 0
                raw_value = select_params.first.split("=", 2)[1]?.try(&.strip) || ""
                # Only set prefix when the value is a quoted string
                # literal. Anything else — `prefix=settings.API_V1_STR`,
                # `prefix=f"{base}/v1"`, `prefix=API_PREFIX` — is a
                # cross-file reference we can't resolve from the call
                # site alone. Letting the raw expression flow through
                # to `router_class.join` used to surface garbage URLs
                # like `/settings.API_V1_STR/me` (regression seen on
                # full-stack-fastapi-template). Try one more rescue
                # path before falling back to empty: when the value
                # is a bare top-level constant (`API_V1_STR`) imported
                # via `from … import …`, look up its definition.
                if lit = raw_value.match(/^['"]([^'"]*)['"]/)
                  prefix = lit[1]
                elsif resolved = resolve_string_expression(raw_value, source, import_modules)
                  prefix = resolved
                end
              end
            end

            # Register router's prefix recursively
            prefix = router_class.join(prefix)
            if router_instance_name.count(".") == 0
              next unless import_modules.has_key?(router_instance_name)
              import_module_path = import_modules[router_instance_name].first

              next unless include_router_map.has_key?(import_module_path)
              configure_router_prefix(import_module_path, include_router_map, prefix)
            elsif router_instance_name.count(".") == 1
              module_name, _router_instance_name = router_instance_name.split(".")
              next unless import_modules.has_key?(module_name)
              import_module_path = import_modules[module_name].first

              next unless include_router_map.has_key?(import_module_path)
              configure_router_prefix(import_module_path, include_router_map, prefix)
            end
          end
        end
      end
    end

    # Best-effort resolver for a non-literal `prefix=` expression in
    # `include_router(...)`. Handles two shapes the wild produces:
    #
    #   * `prefix=API_V1_STR` — a top-level constant imported via
    #     `from app.core.config import API_V1_STR`. We look up the
    #     constant's defining module via `import_modules` and search
    #     it for `NAME = "literal"`.
    #   * `prefix=settings.API_V1_STR` — class-attribute access on an
    #     imported instance. We look up `settings`'s module and search
    #     it for `API_V1_STR: str = "literal"` (the BaseSettings shape
    #     full-stack-fastapi-template uses) or `API_V1_STR = "literal"`.
    #
    # Returns nil when the expression doesn't match either shape or
    # we can't find the underlying file — the caller then falls back
    # to an empty prefix so we never surface raw Python expressions
    # in URLs.
    def resolve_constant_value(expression : ::String,
                               import_modules : Hash(::String, Tuple(::String, Int32))) : ::String?
      expr = expression.strip
      module_path = nil
      const_name = nil

      if attr_match = expr.match(/^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)$/)
        module_alias, attr_name = attr_match[1], attr_match[2]
        return unless import_modules.has_key?(module_alias)
        module_path = import_modules[module_alias].first
        const_name = attr_name
      elsif name_match = expr.match(/^([A-Za-z_][A-Za-z0-9_]*)$/)
        bare_name = name_match[1]
        return unless import_modules.has_key?(bare_name)
        module_path = import_modules[bare_name].first
        const_name = bare_name
      end

      return unless module_path && const_name
      return unless File.exists?(module_path)

      module_source = read_file_content(module_path)
      # Match either a typed assignment (`NAME: str = "..."`) or a
      # bare assignment (`NAME = "..."`). Indented assignments are
      # accepted because BaseSettings-style configs nest the
      # constant inside a class body.
      pattern = /^\s*#{Regex.escape(const_name)}\s*(?::[^=]+)?=\s*['"]([^'"]*)['"]/m
      if match = module_source.match(pattern)
        return match[1]
      end

      nil
    end

    private def resolve_string_expression(expression : ::String,
                                          source : ::String,
                                          import_modules : Hash(::String, Tuple(::String, Int32)),
                                          depth : Int32 = 0) : ::String?
      return if depth > 3

      expr = expression.strip
      if lit = expr.match(/^([rRuUbBfF]*)['"]([^'"]*)['"]/)
        prefixes = lit[1].downcase
        value = lit[2]
        return if prefixes.includes?("f") && value.includes?("{")
        return value
      end

      if local = resolve_constant_in_source(expr, source, import_modules, depth)
        return local
      end

      resolve_constant_value(expr, import_modules)
    end

    private def resolve_constant_in_source(expression : ::String,
                                           source : ::String,
                                           import_modules : Hash(::String, Tuple(::String, Int32)),
                                           depth : Int32) : ::String?
      return unless expression.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)
      pattern = /^\s*#{Regex.escape(expression)}\s*(?::[^=]+)?=\s*([^#]+)/
      source.each_line do |line|
        next unless match = line.match(pattern)
        raw_value = match[1].strip
        next if raw_value.empty?
        return resolve_string_expression(raw_value, source, import_modules, depth + 1)
      end
      nil
    end

    private def extract_python_keyword_expression(call_tail : ::String, keyword : ::String) : ::String?
      match = call_tail.match(/\b#{Regex.escape(keyword)}\s*=/)
      return unless match

      index = match.end
      expression = String.build do |io|
        depth = 0
        in_quote = nil
        escaped = false
        while index < call_tail.size
          ch = call_tail[index]
          if in_quote
            io << ch
            if escaped
              escaped = false
            elsif ch == '\\'
              escaped = true
            elsif ch == in_quote
              in_quote = nil
            end
          else
            case ch
            when '\'', '"'
              in_quote = ch
              io << ch
            when '(', '[', '{'
              depth += 1
              io << ch
            when ')', ']', '}'
              break if depth <= 0 && ch == ')'
              depth -= 1 if depth > 0
              io << ch
            when ','
              break if depth == 0
              io << ch
            else
              io << ch
            end
          end
          index += 1
        end
      end.strip

      expression.empty? ? nil : expression
    end

    # Infers the type of the parameter based on its default value or type annotation
    def infer_parameter_type(data : ::String, is_param_type = false) : ::String?
      if data.matches?(/Cookie/)
        "cookie"
      elsif data.matches?(/Header/)
        "header"
      elsif data.matches?(/Body/) || data.matches?(/Form/) ||
            data.matches?(/File/) || data.matches?(/UploadFile/)
        "form"
      elsif data.matches?(/Query/)
        "query"
      elsif data.matches?(/WebSocket/)
        "websocket"
      elsif is_param_type
        # default variable type
        ["str", "int", "float", "bool", "EmailStr"].each do |type|
          return "query" if data.includes?(type)
        end
      end
    end

    # Finds the parameters for a base model class
    def find_base_model_params(source : ::String, class_name : ::String, param_name : ::String) : Array(Param)
      params = [] of Param
      class_codeblock = parse_code_block(source, /\s*class\s*#{class_name}\s*\(/)
      return params if class_codeblock.nil?

      # Parse the class code block to extract parameters
      class_codeblock.split("\n").each_with_index do |line, index|
        if index == 0
          param_code = line.split("(", 2)[-1].split(")")[0]
          if param_code.match(/(\b)*str,\s*(enum\.){0,1}Enum(\b)*/)
            return [Param.new(param_name.strip, "", "query")]
          end
          return params unless /^#{PYTHON_VAR_NAME_REGEX}$/.match(param_code)
        else
          break unless line.split(":").size == 2

          param_name, extra = line.split(":", 2)
          param_default = ""
          param_type_and_default = extra.split("=", 2)
          if param_type_and_default.size == 2
            param_type, param_default = param_type_and_default
          else
            param_type = param_type_and_default[0]
          end

          if !param_name.empty? && !param_type.empty?
            default_value = return_literal_value(param_default.strip)
            params << Param.new(param_name.strip, default_value, "form")
          end
        end
      end

      params
    end

    # Finds parameters in dictionary structures
    def find_dictionary_params(source : ::String, param : FunctionParameter) : Array(Param)
      new_params = [] of Param
      json_variable_names = [] of ::String
      codelines = source.split("\n")
      if param.type == "Request"
        # Parse JSON variable names
        codelines.each do |codeline|
          match = codeline.match /(#{PYTHON_VAR_NAME_REGEX})\s*(?::\s*#{PYTHON_VAR_NAME_REGEX})?\s*=\s*(await\s*){0,1}#{param.name}.json\(\)/
          json_variable_names << match[1] if !match.nil? && !json_variable_names.includes?(match[1])
        end

        new_params = find_json_params(codelines, json_variable_names)
      elsif param.type == "dict"
        json_variable_names << param.name
        new_params = find_json_params(codelines, json_variable_names)
      end

      new_params
    end

    # Like `coalesce_decorator_call`, but for the programmatic
    # `<instance>.add_api_route(...)` / `add_api_websocket_route(...)`
    # registration form. The opening shape doesn't have `@` so it
    # needs a different regex to detect the call start.
    private def coalesce_programmatic_call(codelines : Array(::String),
                                           index : Int32,
                                           line : ::String,
                                           instance_name : ::String) : ::String
      return line unless line.matches?(/\b#{instance_name}\.(add_api_route|add_api_websocket_route)\s*\(/)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end
      pieces.join(' ')
    end

    private def coalesce_constructor_call(codelines : Array(::String),
                                          index : Int32,
                                          line : ::String,
                                          constructor_name : ::String) : ::String
      return line unless line.matches?(/\b#{Regex.escape(constructor_name)}\s*\(/)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end
      pieces.join(' ')
    end

    # Extract `methods=[...]` / `methods=("...")` from a FastAPI
    # `@router.api_route(...)` / `@router.route(...)` decorator tail.
    # Returns the upper-cased verbs in declaration order; empty list
    # means the decorator didn't declare any methods (caller falls
    # back to the verb implied by the attribute name).
    private def extract_declared_methods(extra_params : ::String) : Array(::String)
      methods = [] of ::String
      list_match = extra_params.match(/methods\s*=\s*[\[(]([^\])]*)[\])]/)
      if list_match
        list_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
          methods << m[1].upcase
        end
      end
      methods
    end

    # If `line` is the start of an `@instance.method(...)` decorator
    # call whose opening paren isn't balanced on the same line, fold
    # the continuation lines into one logical string. Returns `line`
    # unchanged when the call is single-line or doesn't match an
    # `@instance.<method>(` shape. The decorator's `(` and `)` are
    # joined with the continuation content via single-space separators
    # so the downstream regex sees a familiar single-line shape.
    private def coalesce_decorator_call(codelines : Array(::String),
                                        index : Int32,
                                        line : ::String,
                                        instance_name : ::String) : ::String
      return line unless line.matches?(/^\s*@#{instance_name}\.[a-zA-Z_]+\s*\(/)
      return line if python_call_balanced?(line)

      pieces = [line]
      depth = python_paren_delta(line)
      i = index + 1
      while i < codelines.size && depth > 0
        nxt = codelines[i]
        pieces << nxt
        depth += python_paren_delta(nxt)
        break if depth <= 0
        i += 1
      end

      pieces.join(' ')
    end

    # Rewrite `@instance.method(..., path="X", ...)` so `"X"` is the
    # first positional argument. Lets the main scan regex (which
    # expects `(<string>` right after the open paren) catch FastAPI
    # declarations that pass the path via the `path=` keyword. No-op
    # when no `path=` keyword is present.
    private def lift_path_keyword(line : ::String, instance_name : ::String) : ::String
      return line unless line.includes?("path=") || line.includes?("path =")
      return line if line =~ /@#{instance_name}\.[a-zA-Z_]+\s*\(\s*[rf]?['"]/
      match = line.match(/^(?<lead>.*@#{instance_name}\.[a-zA-Z_]+\s*\()(?<rest>.*\bpath\s*=\s*[rf]?['"](?<path>[^'"]*)['"].*)$/m)
      return line unless match
      "#{match["lead"]}\"#{match["path"]}\", #{match["rest"]}"
    end

    # Net `(` − `)` paren count for `line`, ignoring parens inside
    # single- or double-quoted strings. Sufficient for FastAPI
    # decorator headers, which don't carry triple-quoted strings or
    # raw f-strings on the call line itself.
    private def python_paren_delta(line : ::String) : Int32
      depth = 0
      in_quote = nil
      escaped = false
      line.each_char do |ch|
        if in_quote
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
        when '('
          depth += 1
        when ')'
          depth -= 1
        end
      end
      depth
    end

    # Whether `line`'s paren count is balanced (delta == 0). Used to
    # short-circuit the multi-line join when the call already closes
    # on the same line.
    private def python_call_balanced?(line : ::String) : Bool
      python_paren_delta(line) == 0
    end
  end

  # Router class for handling URL prefix joining
  class Router
    @prefix : ::String

    def initialize(prefix : ::String)
      @prefix = prefix
    end

    def prefix
      @prefix
    end

    def join(url : ::String) : ::String
      url = url[1..] if prefix.ends_with?("/") && url.starts_with?("/")
      url = "/#{url}" unless prefix.ends_with?("/") || url.starts_with?("/")

      @prefix + url
    end

    def prefix=(new_prefix : ::String)
      @prefix = new_prefix
    end
  end

  # Extend ::String class to check if a string is numeric
  class ::String
    def numeric?
      to_f != nil rescue false
    end
  end
end
