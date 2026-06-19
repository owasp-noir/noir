require "../../engines/go_engine"
require "../../../miniparsers/go_request_param_extractor"

module Analyzer::Go
  class Http < GoEngine
    IMPORT_MARKER = "net/http"

    def analyze
      # Source Analysis
      # We only need the file_contents cache (and the side-effect of having
      # walked with the import marker). Groups are irrelevant for net/http.
      _, file_contents = collect_package_groups_ts(import_marker: IMPORT_MARKER)
      package_function_bodies = collect_package_function_bodies(file_contents)
      package_method_bodies = collect_package_controller_method_bodies(file_contents)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
      route_dirs = Set(String).new
      file_contents.each do |path, content|
        dir = File.dirname(path)
        if framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["HandleFunc", "Handle"])
          route_dirs << dir
        end
      end
      request_function_bodies = Noir::GoRequestParamExtractor.package_function_bodies_for_dirs(file_contents, route_dirs)
      request_method_bodies = Noir::GoRequestParamExtractor.package_method_bodies_for_dirs(file_contents, route_dirs)
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
                    dir = File.dirname(path)
                    next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["HandleFunc", "Handle"])
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_net_http_routes(content)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin/Mux).
                    route_rows = Set(Int32).new
                    route_methods_by_row = Hash(Int32, String).new
                    routes_by_line.each do |row, routes|
                      route_rows << row
                      route_methods_by_row[row] = routes.first.verb
                    end
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
                    external_methods = ts_controller_method_bodies_for_directory(package_method_bodies, dir)
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)
                    request_fns = Noir::GoRequestParamExtractor.function_bodies_for_directory(request_function_bodies, dir)
                    request_methods = Noir::GoRequestParamExtractor.method_bodies_for_directory(request_method_bodies, dir)
                    params_by_route = Noir::GoRequestParamExtractor.params_for_routes(content, route_rows, route_methods_by_row, request_fns, request_methods)

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          verbs = if route.verb.upcase == "ANY" || route.verb.upcase == "ALL"
                                    Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb)
                                  else
                                    [route.verb]
                                  end
                          verbs.each do |verb|
                            new_endpoint = Endpoint.new(route.path, verb, details)
                            if entries = callees_by_route[route.line]?
                              entries.each do |entry|
                                name, callee_path, callee_line = entry
                                new_endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
                              end
                            end
                            if params = params_by_route[route.line]?
                              params.each { |param| add_param_to_endpoint(param, new_endpoint) }
                            end
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      # Handle parameter extraction patterns in Go (identical to mux / stdlib Request usage).
                      # Order: more specific first.
                      if line.includes?("Query().Get(")
                        add_param_to_endpoint(get_param(line, "Query"), last_endpoint)
                      elsif line.includes?("PostFormValue(")
                        add_param_to_endpoint(get_param(line, "PostFormValue", last_endpoint), last_endpoint)
                      elsif line.includes?("FormValue(")
                        add_param_to_endpoint(get_param(line, "FormValue", last_endpoint), last_endpoint)
                      elsif line.includes?("Header.Get(")
                        add_param_to_endpoint(get_param(line, "Header"), last_endpoint)
                      elsif line.includes?("Cookie(")
                        add_param_to_endpoint(get_param(line, "Cookie"), last_endpoint)
                      end

                      # Stdlib-style body reads (json or raw) — same heuristic used by mux analyzer.
                      if !last_endpoint.url.empty? &&
                         (line.matches?(/json\.NewDecoder\([^)]*\.Body\)\s*\.\s*Decode/) ||
                         line.matches?(/(?:io|ioutil)\.ReadAll\([^)]*\.Body\)/))
                        body_param = Param.new("body", "", "json")
                        last_endpoint.params << body_param unless last_endpoint.params.includes?(body_param)
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
      rescue e
        logger.debug e
      end

      result
    end

    def get_param(line : String, pattern : String, endpoint : Endpoint? = nil) : Param
      param_name = ""
      param_type = ""

      case pattern
      when "Query"
        if match = line.match(/Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "query"
        end
      when "PostFormValue"
        if match = line.match(/PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "form"
        end
      when "FormValue"
        if match = line.match(/FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = form_value_param_type(endpoint)
        end
      when "Header"
        if match = line.match(/Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "header"
        end
      when "Cookie"
        if match = line.match(/Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
          param_name = match[1]
          param_type = "cookie"
        end
      end

      Param.new(param_name, "", param_type)
    end

    private def form_value_param_type(endpoint : Endpoint?) : String
      return "query" unless endpoint

      case endpoint.method
      when "GET", "HEAD", ""
        "query"
      else
        "form"
      end
    end
  end
end
