require "../../../models/analyzer"
require "../../../miniparsers/go_callee_extractor"
require "../../../miniparsers/go_route_extractor_ts"
require "../../engines/go_engine"

module Analyzer::Go
  class Fasthttp < Analyzer
    IMPORT_MARKER = "github.com/valyala/fasthttp"

    def analyze
      # Source Analysis
      begin
        # Pulls from the detector-built file_map so subtree pruning and
        # --exclude-path apply to this pass too.
        go_files = get_files_by_extension(".go")

        # Pre-pass for cross-file identifier-handler resolution.
        # Fasthttp extends `Analyzer` directly (not `GoEngine`), so we
        # build the file_contents hash inline and use the module-level
        # twins on `GoCalleeExtractor`.
        file_contents = Hash(String, String).new
        go_files.each do |fp|
          next if File.directory?(fp)
          next if GoEngine.go_test_file?(fp)
          begin
            file_contents[fp] = read_file_content(fp)
          rescue File::NotFoundError
            # skip
          end
        end
        package_function_bodies = Noir::GoCalleeExtractor.package_function_bodies_if(callees_needed?, file_contents)
        # Resolve method-value handlers (`h.Index`) to their bodies too,
        # so callees aren't empty when handlers hang off a struct.
        package_method_bodies = Noir::GoCalleeExtractor.package_method_bodies_if(callees_needed?, file_contents)

        base_paths.each do |current_base_path|
          go_files.each do |path|
            next unless path_under_root?(path, current_base_path)
            next if GoEngine.go_test_file?(path)
            if File.exists?(path)
              content = read_file_content(path)
              next unless content.includes?(IMPORT_MARKER)
              last_endpoint = Endpoint.new("", "")

              # Tree-sitter pre-pass: fasthttp has no groups, so we just
              # pull every `<router>.<VERB>("/path", ...)` the extractor
              # finds. The extra string constraint (`"/..."`) the legacy
              # regex enforced is already covered — `decode_verb_call`
              # returns nil when the first string arg is empty.
              ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content)
              routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
              ts_routes.each do |r|
                # Fasthttp accepts paths starting with `/`; drop anything
                # else (the legacy regex had the same constraint).
                next unless r.raw_path.starts_with?("/")
                routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                routes_by_line[r.line] << r
              end

              # Resolve 1-hop callees for every route (see Gin).
              route_rows = Set(Int32).new
              routes_by_line.each_key { |row| route_rows << row }
              external_fns = Noir::GoCalleeExtractor.function_bodies_for_directory(package_function_bodies, File.dirname(path))
              external_methods = Noir::GoCalleeExtractor.method_bodies_for_directory(package_method_bodies, File.dirname(path))
              callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)

              content.each_line.with_index do |line, index|
                details = Details.new(PathInfo.new(path, index + 1))

                if ts_hits = routes_by_line[index]?
                  ts_hits.each do |route|
                    clean_path = normalize_fasthttp_path(route.path)
                    Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                      endpoint = Endpoint.new(clean_path, verb, details)
                      if entries = callees_by_route[route.line]?
                        entries.each do |entry|
                          name, callee_path, callee_line = entry
                          endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                        end
                      end
                      result << endpoint
                      last_endpoint = endpoint
                    end
                  end
                end

                params = analyze_param_line(line)
                params.each do |param|
                  if param.name.size > 0 && !last_endpoint.method.empty?
                    unless last_endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
                      last_endpoint.params << param
                    end
                  end
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    # Normalize fasthttp/router path-parameter syntax into the canonical
    # `{name}` placeholder. fasthttp/router accepts optional params
    # (`{name?}`), inline regex constraints (`{name:[0-9]+}`), and the
    # two combined (`{name?:[a-zA-Z]+}`). The optimizer's generic
    # `{name:regex}` stripper only matches identifier-then-colon, so the
    # `?` optional marker leaks through as part of the param name
    # (`name?`) and the URL keeps its regex body. Strip both here so the
    # surfaced URL and the path-param names are clean.
    private def normalize_fasthttp_path(path : String) : String
      path.gsub(/\{([a-zA-Z0-9_]+)\??(?::[^{}]+)?\}/) { "{#{$1}}" }
    end

    private def analyze_route_line(line : String, details : Details) : Endpoint
      # Pattern 1: Direct handler registration with router
      # router.GET("/path", handler) or router.POST("/path", handler)
      # Route path must start with "/" to be a valid HTTP endpoint
      if match = line.match(/(?:router|r|app|server)\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*"(\/[^"]*)"\s*,/)
        path = match[1]
        method = extract_method_from_router_call(line)
        return Endpoint.new(path, method, details)
      end

      # Pattern 2: fasthttprouter patterns
      # router.GET("/path", handler)
      # Route path must start with "/" to be a valid HTTP endpoint
      if match = line.match(/\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*"(\/[^"]*)"\s*,/)
        path = match[1]
        method = extract_method_from_router_call(line)
        return Endpoint.new(path, method, details)
      end

      # Pattern 3: Direct fasthttp.ListenAndServe with switch statements for routes
      # This would require more complex analysis, for now we focus on router patterns

      Endpoint.new("", "")
    end

    private def extract_method_from_router_call(line : String) : String
      if match = line.match(/\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)/)
        match[0].gsub(".", "").upcase
      else
        ""
      end
    end

    private def analyze_param_line(line : String) : Array(Param)
      params = [] of Param

      # QueryArgs().Peek("param") or QueryArgs().Get("param")
      line.scan(/(?:QueryArgs|PostArgs)\(\)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        param_type = line.includes?("QueryArgs") ? "query" : "form"
        params << Param.new(param_name, "", param_type)
      end

      # ctx.QueryArgs().Peek("param")
      line.scan(/ctx\.(?:QueryArgs|PostArgs)\(\)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        param_type = line.includes?("QueryArgs") ? "query" : "form"
        params << Param.new(param_name, "", param_type)
      end

      # Request.Header.Peek("header")
      line.scan(/(?:Request\.Header|ctx\.Request\.Header)\.(?:Peek|PeekMulti|Get|GetAll)\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "header")
      end

      # Cookie access: ctx.Request.Header.Cookie("name")
      line.scan(/(?:Request\.Header|ctx\.Request\.Header)\.Cookie\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "cookie")
      end

      # Form values: ctx.FormValue("param")
      line.scan(/ctx\.FormValue\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "form")
      end

      # UserValue for path parameters: ctx.UserValue("param")
      line.scan(/ctx\.UserValue\s*\(\s*"([^"]+)"\s*\)/) do |match|
        param_name = match[1]
        params << Param.new(param_name, "", "path")
      end

      # Body access: fasthttp exposes the raw body via `ctx.PostBody()`
      # or `ctx.Request.Body()`. A handler that reads either is consuming
      # a request body — surface a single body indicator (the body is
      # usually subsequently passed to json.Unmarshal which we can't
      # always pin to a specific field set).
      if line.includes?("ctx.PostBody(") || line.includes?(".Request.Body(") ||
         line.matches?(/json\.Unmarshal\([^)]*\.PostBody\(\)/)
        params << Param.new("body", "", "json")
      end

      params
    end
  end
end
