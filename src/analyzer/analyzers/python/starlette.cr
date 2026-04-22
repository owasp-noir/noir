require "../../engines/python_engine"

module Analyzer::Python
  class Starlette < PythonEngine
    # Route('/path', handler, methods=[...]) — captures path, and the tail
    # after the path literal so we can inspect methods= and the handler
    # reference. The tail stops at the closing paren on the same line to
    # keep the match cheap; multi-line Route() calls are still covered for
    # the common (path, handler, methods) shape.
    ROUTE_REGEX = /Route\s*\(\s*[rf]?['"]([^'"]*)['"]([^)]*)/
    # Mount('/prefix', routes=[...]) — only the prefix literal is needed;
    # the routes list is scanned via the ongoing line loop while the mount
    # is on the paren stack.
    MOUNT_REGEX = /Mount\s*\(\s*[rf]?['"]([^'"]*)['"]/
    # Path param in a route pattern: {name} or {name:type}. Starlette uses
    # the :type suffix as a converter hint (int, str, float, uuid, path);
    # it is stripped before the param is exposed as a query param.
    PATH_PARAM_REGEX       = /\{([a-zA-Z_][a-zA-Z0-9_]*)(?::[a-zA-Z_][a-zA-Z0-9_]*)?\}/
    TYPED_PATH_PARAM_REGEX = /\{([a-zA-Z_][a-zA-Z0-9_]*):[a-zA-Z_][a-zA-Z0-9_]*\}/

    def analyze
      python_files = get_files_by_extension(".py")
      base_paths.each do |current_base_path|
        base_dir_prefix = current_base_path.ends_with?("/") ? current_base_path : "#{current_base_path}/"
        python_files.each do |path|
          next unless path.starts_with?(base_dir_prefix) || path == current_base_path
          next if path.includes?("/site-packages/")

          source = read_file_content(path)
          next unless source.includes?("starlette")

          analyze_file(path, source)
        end
      end

      Fiber.yield
      result
    end

    private def analyze_file(path : ::String, source : ::String)
      lines = source.split("\n")
      # Stack of active Mount prefixes. Each entry stores the paren depth
      # at which the Mount was opened; when the running depth drops below
      # that value the mount has closed and its prefix must be popped.
      mount_stack = [] of Tuple(::String, Int32)
      paren_depth = 0

      lines.each_with_index do |line, line_index|
        line.scan(MOUNT_REGEX) do |match|
          next if match.size < 2
          mount_stack << {match[1], paren_depth + 1}
        end

        line.scan(ROUTE_REGEX) do |match|
          next if match.size < 3
          route_path = match[1]
          tail = match[2]

          methods = [] of ::String
          methods_match = tail.match(/methods\s*=\s*\[([^\]]*)\]/)
          if methods_match
            methods_match[1].scan(/['"]([A-Za-z]+)['"]/) do |m|
              methods << m[1].upcase
            end
          end
          methods << "GET" if methods.empty?

          prefix = mount_stack.map(&.[0]).join
          full_url = "#{prefix}#{route_path}"
          full_url = "/#{full_url}" unless full_url.starts_with?("/")
          full_url = full_url.gsub(TYPED_PATH_PARAM_REGEX) { |_| "{#{$~[1]}}" }

          path_params = extract_path_params(route_path)

          handler_params = [] of Param
          handler_match = tail.match(/,\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
          if handler_match
            handler_params = extract_handler_params(lines, handler_match[1])
          end

          methods.uniq.each do |method|
            params = [] of Param
            path_params.each { |p| params << p }
            handler_params.each do |p|
              next if params.any? { |existing| existing.name == p.name && existing.param_type == p.param_type }
              params << p
            end

            details = Details.new(PathInfo.new(path, line_index + 1))
            result << Endpoint.new(full_url, method, params, details)
          end
        end

        paren_depth += line.count('(') - line.count(')')
        paren_depth = 0 if paren_depth < 0
        while !mount_stack.empty? && mount_stack.last[1] > paren_depth
          mount_stack.pop
        end
      end
    end

    private def extract_path_params(route_path : ::String) : Array(Param)
      params = [] of Param
      route_path.scan(PATH_PARAM_REGEX) do |match|
        name = match[1]
        next if params.any? { |p| p.name == name }
        params << Param.new(name, "", "query")
      end
      params
    end

    private def extract_handler_params(lines : Array(::String), handler_name : ::String) : Array(Param)
      params = [] of Param

      lines.each_with_index do |line, idx|
        def_match = line.match(/def\s+#{Regex.escape(handler_name)}\s*\(\s*([a-zA-Z_][a-zA-Z0-9_]*)/)
        next unless def_match
        request_name = def_match[1]

        codeblock = parse_code_block(lines[idx..])
        break if codeblock.nil?
        codeblock.split("\n").each do |cl|
          collect_request_attr_params(cl, request_name, "path_params", "query", params)
          collect_request_attr_params(cl, request_name, "query_params", "query", params)
          collect_request_attr_params(cl, request_name, "headers", "header", params)
          collect_request_attr_params(cl, request_name, "cookies", "cookie", params)

          if cl.matches?(/await\s+#{Regex.escape(request_name)}\.json\s*\(/)
            add_unique(params, Param.new("body", "", "json"))
          end
          if cl.matches?(/await\s+#{Regex.escape(request_name)}\.form\s*\(/)
            add_unique(params, Param.new("body", "", "form"))
          end
        end
        break
      end

      params
    end

    private def collect_request_attr_params(line : ::String, request_name : ::String, attr : ::String, noir_type : ::String, params : Array(Param))
      line.scan(/#{Regex.escape(request_name)}\.#{attr}\[\s*[rf]?['"]([^'"]+)['"]\s*\]/) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
      line.scan(/#{Regex.escape(request_name)}\.#{attr}\.get\(\s*[rf]?['"]([^'"]+)['"]/) do |m|
        add_unique(params, Param.new(m[1], "", noir_type))
      end
    end

    private def add_unique(params : Array(Param), param : Param)
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end
  end
end
