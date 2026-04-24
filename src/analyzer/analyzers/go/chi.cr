require "../../../models/analyzer"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  private class ChiRouteState
    property prefix_stack : Array(String) = [] of String
    property? in_inline_handler : Bool = false
    property handler_brace_count : Int32 = 0
  end

  class Chi < Analyzer
    def analyze
      result = [] of Endpoint

      # Pre-scan: collect per-directory file lists, mounted function names,
      # file contents, and TS-resolved route lists for each file.
      package_mounted_functions = Hash(String, Set(String)).new
      package_files = Hash(String, Array(String)).new
      file_contents_cache = Hash(String, String).new
      file_lines_cache = Hash(String, Array(String)).new

      get_files_by_extension(".go").each do |scan_path|
        next if File.directory?(scan_path)
        begin
          dir = File.dirname(scan_path)
          package_files[dir] ||= [] of String
          package_files[dir] << scan_path

          content = File.read(scan_path, encoding: "utf-8", invalid: :skip)
          file_contents_cache[scan_path] = content
          file_lines_cache[scan_path] = content.lines

          # Mount targets still need a regex sweep — the name that appears
          # in `r.Mount("/admin", adminRouter())` is a *symbol*, not a
          # route, and it determines which function bodies to exclude from
          # the free-floating TS extraction pass below.
          content.each_line do |scan_line|
            if scan_line.includes?(".Mount(")
              if scan_match = scan_line.match(/[a-zA-Z]\w*\.Mount\(\s*"([^"]+)"\s*,\s*([^(]+)\(\)/)
                package_mounted_functions[dir] ||= Set(String).new
                package_mounted_functions[dir] << scan_match[2].strip
              end
            end
          end
        rescue File::NotFoundError
          # skip
        end
      end

      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        populate_channel_with_filtered_files(channel, ".go")

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                path = channel.receive?
                break if path.nil?
                next if File.directory?(path)
                if File.exists?(path)
                  content = file_contents_cache[path]? || File.read(path, encoding: "utf-8", invalid: :skip)
                  lines = file_lines_cache[path]? || content.lines

                  dir = File.dirname(path)
                  mounted_functions = package_mounted_functions.fetch(dir, Set(String).new)

                  # Tree-sitter pre-pass: every `r.Get(...)` / `r.Route(...)`
                  # / `r.Group(...)` resolved with the correct prefix, skipping
                  # bodies of functions that are expanded via Mount (those
                  # are handled below to get their `/admin` prefix).
                  ts_routes = Noir::TreeSitterGoRouteExtractor
                    .extract_chi_routes(content, mounted_functions)
                  routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                  ts_routes.each do |r|
                    routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                    routes_by_line[r.line] << r
                  end

                  state = ChiRouteState.new
                  last_endpoint = Endpoint.new("", "")
                  in_mounted_func = false
                  mounted_func_brace_count = 0

                  lines.each_with_index do |line, index|
                    # Skip bodies of mounted router functions so parameter
                    # extraction only attributes them to the Mount-expanded
                    # endpoints, not the free-floating verb calls we now
                    # skip in the TS pass.
                    if in_mounted_func
                      mounted_func_brace_count += line.count("{")
                      mounted_func_brace_count -= line.count("}")
                      if mounted_func_brace_count <= 0
                        in_mounted_func = false
                      end
                      next
                    end
                    if !mounted_functions.empty? && line.strip.starts_with?("func ")
                      if func_match = line.match(/func\s+([a-zA-Z_]\w*)\s*\(/)
                        if mounted_functions.includes?(func_match[1])
                          in_mounted_func = true
                          mounted_func_brace_count = line.count("{") - line.count("}")
                          if mounted_func_brace_count <= 0
                            in_mounted_func = false
                          end
                          next
                        end
                      end
                    end

                    details = Details.new(PathInfo.new(path, index + 1))

                    if line.includes?(".Mount(")
                      if match = line.match(/[a-zA-Z]\w*\.Mount\(\s*"([^"]+)"\s*,\s*([^(]+)\(\)/)
                        mount_prefix = match[1]
                        router_function = match[2]
                        endpoints = analyze_router_function(path, router_function, package_files, file_contents_cache, file_lines_cache)
                        endpoints.each do |ep|
                          ep.url = mount_prefix + ep.url
                          result << ep
                        end
                      end
                      next
                    end

                    # Emit any route whose declaration begins on this line,
                    # and seed inline-handler tracking so the param extractor
                    # below only attributes params to the enclosing route.
                    if ts_hits = routes_by_line[index]?
                      ts_hits.each do |route|
                        endpoint = Endpoint.new(route.path, route.verb, details)
                        result << endpoint
                        last_endpoint = endpoint
                      end
                      if line.includes?("func(")
                        state.in_inline_handler = true
                        state.handler_brace_count = line.count("{") - line.count("}")
                        if state.handler_brace_count <= 0
                          state.in_inline_handler = false
                          state.handler_brace_count = 0
                        end
                      end
                    elsif state.in_inline_handler?
                      # Normal line inside an inline handler — tally braces
                      # so we know when it closes.
                      state.handler_brace_count += line.count("{")
                      state.handler_brace_count -= line.count("}")
                      if state.handler_brace_count <= 0
                        state.in_inline_handler = false
                        state.handler_brace_count = 0
                      end
                    end

                    extract_params(line, state, last_endpoint)
                  end
                end
              rescue File::NotFoundError
                logger.debug "File not found: #{path}"
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      result
    end

    private def extract_params(line : String, state : ChiRouteState, last_endpoint : Endpoint)
      return if last_endpoint.url.empty?
      return unless state.in_inline_handler?

      # Parameter extraction patterns (order matters - check more specific patterns first)
      pattern = if line.includes?("chi.URLParam(")
                  "URLParam"
                elsif line.includes?("Query().Get(")
                  "Query"
                elsif line.includes?("PostFormValue(")
                  "PostFormValue"
                elsif line.includes?("FormValue(")
                  "FormValue"
                elsif line.includes?("Header.Get(")
                  "Header"
                elsif line.includes?("Cookie(")
                  "Cookie"
                end

      if pattern
        param = get_param(line, pattern)
        last_endpoint.params << param unless param.name.empty?
      end
    end

    def get_param(line : String, pattern : String) : Param
      param_name = ""
      param_type = ""

      # Special handling for different patterns
      case pattern
      when "URLParam"
        # Handle chi.URLParam(r, "id") pattern
        if match = line.match(/chi\.URLParam\([^,]+,\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "path"
        end
      when "Query"
        # Handle r.URL.Query().Get("name") pattern
        if match = line.match(/Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "query"
        end
      when "PostFormValue"
        # Handle r.PostFormValue("username") pattern
        if match = line.match(/PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "form"
        end
      when "FormValue"
        # Handle r.FormValue("password") pattern
        if match = line.match(/FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "form"
        end
      when "Header"
        # Handle r.Header.Get("User-Agent") pattern
        if match = line.match(/Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "header"
        end
      when "Cookie"
        # Handle r.Cookie("auth_token") pattern
        if match = line.match(/Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "cookie"
        end
      end

      Param.new(param_name, "", param_type)
    end

    # Extracts endpoints from a router function definition, searching across
    # all .go files in the same directory (Go package) if not found in the
    # given file.
    #
    # Uses the tree-sitter walker too, but scoped down to just the target
    # function's declaration so the returned routes are relative to the
    # function body — caller slaps on the Mount prefix.
    def analyze_router_function(file_path : String, func_name : String,
                                package_files : Hash(String, Array(String))? = nil,
                                file_contents_cache : Hash(String, String)? = nil,
                                file_lines_cache : Hash(String, Array(String))? = nil) : Array(Endpoint)
      endpoints = [] of Endpoint

      # Search: given file first, then other files in the same directory.
      dir = File.dirname(file_path)
      search_files = [file_path]
      if package_files && package_files.has_key?(dir)
        package_files[dir].each do |other_path|
          search_files << other_path unless other_path == file_path
        end
      end

      search_files.each do |search_path|
        content =
          (file_contents_cache.try &.[search_path]?) ||
            begin
              File.read(search_path, encoding: "utf-8", invalid: :skip)
            rescue File::NotFoundError
              next
            end

        routes = extract_router_function_routes(content, func_name)
        next if routes.empty?

        # Capture routes' original line numbers on the endpoint details.
        # `attach_router_function_params` uses those to bind parameter
        # lines to the correct endpoint instead of counting verb calls,
        # which would false-positive on `r.Header.Get(...)` / `Query().Get(...)`
        # accessor calls inside inline handlers.
        routes.each do |route|
          details = Details.new(PathInfo.new(search_path, route.line + 1))
          endpoints << Endpoint.new(route.path, route.verb, details)
        end

        lines = (file_lines_cache.try &.[search_path]?) || content.lines
        attach_router_function_params(endpoints, lines)
        break
      end

      endpoints
    end

    # Walks the full tree-sitter tree for `source`, isolating the body of
    # `func <func_name>(...)` and returning only the routes registered
    # there.
    private def extract_router_function_routes(source : String, func_name : String) : Array(Noir::TreeSitterGoRouteExtractor::Route)
      hits = [] of Noir::TreeSitterGoRouteExtractor::Route
      Noir::TreeSitter.parse_go(source) do |root|
        find_func_declaration(root, source, func_name) do |body|
          # Re-run the chi walker against the isolated body. skip_functions
          # is empty because any nested func literal inside is the inline
          # handler which the walker already ignores by convention.
          collected = [] of Noir::TreeSitterGoRouteExtractor::Route
          Noir::TreeSitterGoRouteExtractor.walk_chi_public(body, source, collected)
          collected.each { |c| hits << c }
        end
      end
      hits
    end

    private def find_func_declaration(node : LibTreeSitter::TSNode, source : String, name : String, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "function_declaration"
        if name_node = Noir::TreeSitter.field(node, "name")
          if Noir::TreeSitter.node_text(name_node, source) == name
            if body = Noir::TreeSitter.field(node, "body")
              yield body
              return
            end
          end
        end
      end
      Noir::TreeSitter.each_named_child(node) do |child|
        find_func_declaration(child, source, name, &block)
      end
    end

    # Reattach the line-based param extractor to mount-expanded endpoints.
    # Endpoints arrive with their source line recorded in PathInfo.line
    # (1-based), so we index them by line and switch `last_endpoint`
    # whenever the walker crosses a declaration line — much more robust
    # than counting verb-shaped method calls, since inline handlers
    # invoke `r.Header.Get(...)` and friends that would otherwise shift
    # the iterator off-by-one.
    private def attach_router_function_params(endpoints : Array(Endpoint), lines : Array(String))
      return if endpoints.empty?

      endpoints_by_line = Hash(Int32, Endpoint).new
      endpoints.each do |ep|
        ep.details.code_paths.each do |cp|
          if line = cp.line
            endpoints_by_line[line.to_i - 1] = ep
          end
        end
      end
      return if endpoints_by_line.empty?

      min_line = endpoints_by_line.keys.min
      max_line = endpoints_by_line.keys.max

      state = ChiRouteState.new
      last_endpoint = Endpoint.new("", "")

      # Scan from the earliest declaration line forward until every
      # endpoint has had a chance to absorb its handler body. The handler
      # brace count terminates the body window; we stop when we've gone
      # well past the last endpoint and no handler is open.
      index = min_line
      while index < lines.size
        line = lines[index]
        if ep = endpoints_by_line[index]?
          last_endpoint = ep
          if line.includes?("func(")
            state.in_inline_handler = true
            state.handler_brace_count = line.count("{") - line.count("}")
            if state.handler_brace_count <= 0
              state.in_inline_handler = false
              state.handler_brace_count = 0
            end
          end
        elsif state.in_inline_handler?
          state.handler_brace_count += line.count("{")
          state.handler_brace_count -= line.count("}")
          if state.handler_brace_count <= 0
            state.in_inline_handler = false
            state.handler_brace_count = 0
          end
        end

        extract_params(line, state, last_endpoint)

        break if index > max_line && !state.in_inline_handler?
        index += 1
      end
    end
  end
end
