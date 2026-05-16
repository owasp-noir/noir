require "../../engines/go_engine"

module Analyzer::Go
  class Echo < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      package_groups, file_contents = collect_package_groups_ts
      # Pre-pass for cross-file identifier-handler resolution. Built
      # once per analyze() so each per-file callee pass only does an
      # O(1) lookup into `package_function_bodies` rather than re-
      # walking every sibling source file.
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_filtered_files(channel, ".go")

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path)
                    content = file_contents[path]? || read_file_content(path)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Tree-sitter pre-pass: every Echo verb route
                    # (`e.GET`, `g.POST`, …) with its group prefix applied.
                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route in this file.
                    # Inline-closure handlers walk in place; bare
                    # identifier handlers fall through to sibling-file
                    # function bodies via the per-directory map.
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                    # `e.Static("/url", "./dir")` — same shape as Gin/Fiber/etc.
                    Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                      public_dirs << {"static_path" => sp.url_prefix, "file_path" => sp.disk_path}
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          new_endpoint = Endpoint.new(route.path, route.verb, details)
                          if entries = callees_by_route[route.line]?
                            entries.each do |entry|
                              name, callee_path, callee_line = entry
                              new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                            end
                          end
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      if line.includes?("Param(") || line.includes?("FormValue(")
                        add_param_to_endpoint(get_param(line), last_endpoint)
                      end

                      if line.includes?("Request().Header.Get(")
                        match = line.match(/Request\(\)\.Header\.Get\(\"(.*)\"\)/)
                        if match
                          header_name = match[1]
                          last_endpoint.params << Param.new(header_name, "", "header")
                        end
                      end

                      if line.includes?("Cookie(") &&
                         !line.includes?("Header.Get") && !line.includes?("Query().Get") &&
                         !line.includes?("Request().Header.Get")
                        match = line.match(/Cookie\(\"(.*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
                        end
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
        logger.debug e
      end

      resolve_public_dirs(public_dirs)

      result
    end

    def get_param(line : String) : Param
      param_type = "json"
      if line.includes?("QueryParam")
        param_type = "query"
      end
      if line.includes?("FormValue")
        param_type = "form"
      end

      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(")")
        if second.size > 1
          param_name = second[0].gsub("\"", "")
          rtn = Param.new(param_name, "", param_type)

          return rtn
        end
      end

      Param.new("", "", "")
    end
  end
end
