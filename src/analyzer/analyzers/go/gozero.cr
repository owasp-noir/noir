require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class GoZero < GoEngine
    IMPORT_MARKER = "github.com/zeromicro/go-zero"

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Pre-pass for cross-file identifier-handler resolution. Only
      # `.go` routes (`server.Get("/x", h)` shape) get callees —
      # gozero's `.api` files are a non-Go DSL that declares routes as
      # `get /path (Request)` with an `@handler Name` directive; there's
      # no Go call_expression to extract a 1-hop graph from.
      # `read_package_file_contents` already filters to `.go`, so the
      # function-body map naturally skips `.api`.
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        populate_channel_with_filtered_files(channel, [".go", ".api"])

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)

                  # Handle both .go files and .api files
                  if File.exists?(path) && (File.extname(path) == ".go" || File.extname(path) == ".api")
                    content = read_file_content(path)
                    # `.api` files are gozero's DSL (no Go imports);
                    # only gate `.go` files on the import marker.
                    next if File.extname(path) == ".go" && !content.includes?(IMPORT_MARKER)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Go files: tree-sitter pre-pass (same verb-on-identifier
                    # pattern Gin uses, no groups in gozero's common idioms).
                    # .api files use a non-Go DSL — keep the legacy regex.
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    callees_by_route = Hash(Int32, Array(Tuple(String, String, Int32))).new
                    if File.extname(path) == ".go"
                      Noir::TreeSitterGoRouteExtractor.extract_routes(content).each do |r|
                        next unless r.raw_path.starts_with?("/")
                        routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                        routes_by_line[r.line] << r
                      end
                      Noir::TreeSitterGoRouteExtractor.extract_simple_statics(content).each do |sp|
                        public_dirs << {"static_path" => sp.url_prefix, "file_path" => sp.disk_path}
                      end

                      # Resolve 1-hop callees for every .go route.
                      route_rows = Set(Int32).new
                      routes_by_line.each_key { |row| route_rows << row }
                      external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                      callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Handle .api files (go-zero API definition files)
                      if File.extname(path) == ".api"
                        if match = line.match(/^\s*(get|post|put|delete|patch|head|options)\s+([^\s\(]+)/)
                          method = match[1].upcase
                          route_path = match[2]
                          new_endpoint = Endpoint.new(route_path, method, details)
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      # Handle .go files
                      if File.extname(path) == ".go"
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

                        ["Query", "PostForm", "GetHeader", "PathParam", "FormValue"].each do |pattern|
                          if line.includes?("#{pattern}(")
                            add_param_to_endpoint(get_param(line), last_endpoint)
                          end
                        end
                      end
                    end
                  end
                rescue
                  # Skip problematic files
                  next
                end
              end
            end
          end
        end
      rescue
        # Handle channel errors
      end

      resolve_public_dirs_with_glob(public_dirs)

      result
    end

    def get_param(line : String) : Param
      # Extract parameter name from various go-zero parameter patterns
      # e.g., c.Query("param"), c.PostForm("param"), etc.
      if match = line.match(/\w+\(\"([^"]+)\"\)/)
        param_name = match[1]
        return Param.new(param_name, "", "query")
      end

      Param.new("", "", "")
    end
  end
end
