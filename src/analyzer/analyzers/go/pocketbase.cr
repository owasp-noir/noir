require "../../engines/go_engine"

module Analyzer::Go
  # Pocketbase ships its own HTTP router under
  # `github.com/pocketbase/pocketbase/tools/router`. The DSL mirrors
  # Echo/Gin (`rg.GET("/x", handler)`, `rg.Group("/api")`), so the
  # shared `TreeSitterGoRouteExtractor` already handles the call
  # shapes — this analyzer just wires the import marker so noir
  # opts the framework's source files into the same pipeline.
  class Pocketbase < GoEngine
    IMPORT_MARKER = "pocketbase/tools/router"

    def analyze
      public_dirs = [] of Hash(String, String)
      package_groups, file_contents = collect_package_groups_ts
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
                  next if GoEngine.go_test_file?(path)
                  if File.exists?(path)
                    content = file_contents[path]? || read_file_content(path)
                    next unless content.includes?(IMPORT_MARKER)

                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(content, cross_file_groups)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                    lines = content.lines
                    lines.each_with_index do |_line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            endpoint = Endpoint.new(route.path, verb, details)
                            if entries = callees_by_route[route.line]?
                              entries.each do |entry|
                                name, callee_path, callee_line = entry
                                endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                            end
                            result << endpoint
                          end
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
  end
end
