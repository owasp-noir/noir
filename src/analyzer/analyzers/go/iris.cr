require "../../engines/go_engine"

module Analyzer::Go
  class Iris < GoEngine
    HTTP_METHODS  = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS", "HEAD"]
    IMPORT_MARKER = "github.com/kataras/iris"

    def analyze
      # Iris uses `.Party(...)` for route groups; pass that into both the
      # engine's fixpoint group collection and the per-file extractor.
      package_groups, file_contents = collect_package_groups_ts("Party")
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            get_files_by_extension(".go").each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)
                  if File.exists?(path)
                    content = file_contents[path]? || read_file_content(path)
                    next unless content.includes?(IMPORT_MARKER)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
                      content, cross_file_groups, group_method: "Party"
                    )
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          normalized = normalize_iris_path(route.path)
                          callee_entries = callees_by_route[route.line]?
                          if route.verb == "ANY"
                            HTTP_METHODS.each do |m|
                              new_endpoint = Endpoint.new(normalized, m, details)
                              callee_entries.try &.each do |entry|
                                name, callee_path, callee_line = entry
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          else
                            new_endpoint = Endpoint.new(normalized, route.verb, details)
                            callee_entries.try &.each do |entry|
                              name, callee_path, callee_line = entry
                              new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      ["URLParam", "URLParamDefault", "URLParamTrim",
                       "PostValue", "FormValue",
                       "GetHeader", "GetCookie"].each do |pattern|
                        if line.includes?("#{pattern}(")
                          add_param_to_endpoint(get_param(line, pattern), last_endpoint)
                        end
                      end

                      # Iris exposes a family of body readers — JSON is
                      # most common, but the framework also accepts XML,
                      # YAML, MsgPack, Protobuf, plain Body, and Form
                      # readers. All consume the request body.
                      if line.matches?(/\.Read(?:JSON|XML|YAML|MsgPack|Protobuf|Body|Form)\s*\(/)
                        add_param_to_endpoint(Param.new("body", "", "json"), last_endpoint)
                      end
                    end
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.error "Iris analyzer failed: #{e.message}"
        logger.debug e
      end

      result
    end

    # Strip Iris type annotations from path params: `{id:uint64}` → `{id}`,
    # `{file:path}` → `{file}`. Leaves unadorned `{id}` untouched.
    def normalize_iris_path(path : String) : String
      path.gsub(/\{([^{}:]+):[^{}]+\}/) { "{#{$1}}" }
    end

    def get_param(line : String, pattern : String) : Param
      param_type = case pattern
                   when "URLParam", "URLParamDefault", "URLParamTrim" then "query"
                   when "PostValue", "FormValue"                      then "form"
                   when "GetHeader"                                   then "header"
                   when "GetCookie"                                   then "cookie"
                   else                                                    "json"
                   end

      # Find the specific call — avoids picking up a different `(` earlier on
      # the line (e.g. `foo(ctx.URLParam("x"))`).
      idx = line.index("#{pattern}(")
      return Param.new("", "", "") if idx.nil?

      after = line[(idx + pattern.size + 1)..]
      close = after.index(")")
      return Param.new("", "", "") if close.nil?

      arg = after[0...close].split(",")[0].gsub("\"", "").strip
      return Param.new("", "", "") if arg.empty?

      Param.new(arg, "", param_type)
    end
  end
end
