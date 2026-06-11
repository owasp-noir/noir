require "../../engines/go_engine"

module Analyzer::Go
  class Mux < GoEngine
    IMPORT_MARKER = "github.com/gorilla/mux"

    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Mux subrouters are created via the two-call chain
      # `api := r.PathPrefix("/api/").Subrouter()`. The engine fixpoint
      # treats "Subrouter" as the grouping method and peeks through the
      # chain to read the PathPrefix argument.
      package_groups, file_contents = collect_package_groups_ts("Subrouter", import_marker: IMPORT_MARKER)
      # Pre-pass for cross-file identifier-handler resolution (see Gin).
      # Mux's HandleFunc/Methods chain stores `route.line` on the
      # HandleFunc call_expression itself, so the row-keyed callee
      # lookup matches it cleanly.
      package_function_bodies = collect_package_function_bodies(file_contents)
      # Mux handlers are almost always method values (`as.Campaigns`) or
      # wrapped method values (`mid.Use(as.Users, ...)`); resolve them to
      # their method bodies so callees/ai-context aren't empty.
      package_method_bodies = collect_package_controller_method_bodies(file_contents)
      framework_dirs = framework_package_dirs(file_contents, IMPORT_MARKER)
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
                    next unless framework_route_source_candidate?(content, dir, framework_dirs, IMPORT_MARKER, ["Handle", "HandleFunc", "Path", "PathPrefix", "Methods", "Queries"])
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    cross_file_groups = ts_groups_for_directory(package_groups, dir)
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
                      content, cross_file_groups,
                      group_method: "Subrouter",
                      handlefunc_methods: true,
                    )
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    # Resolve 1-hop callees for every route (see Gin).
                    route_rows = Set(Int32).new
                    routes_by_line.each_key { |row| route_rows << row }
                    external_fns = ts_function_bodies_for_directory(package_function_bodies, dir)
                    external_methods = ts_controller_method_bodies_for_directory(package_method_bodies, dir)
                    callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns, external_methods)

                    # Mux static-file: `r.PathPrefix("/x/").Handler(... http.Dir("./x/") ...)`
                    Noir::TreeSitterGoRouteExtractor.extract_mux_statics(content).each do |sp|
                      public_dirs << static_dir_entry(path, sp.url_prefix, sp.disk_path)
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
                            new_endpoint = Endpoint.new(route.path, verb, details)
                            # mux's `.Queries("type", "{type}", ...)` declares
                            # required query params; bind them to the endpoint.
                            route.query_params.each do |qp|
                              new_endpoint.params << Param.new(qp, "", "query")
                            end
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
                      end

                      # Handle parameter extraction patterns in Go (order matters - check more specific patterns first)
                      if line.includes?("Vars(")
                        add_param_to_endpoint(get_param(line, "Vars"), last_endpoint)
                      elsif line.includes?("Query().Get(")
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

                      # Stdlib-style body reads. Gorilla/mux apps almost
                      # always use `json.NewDecoder(r.Body).Decode(&v)`
                      # or `io.ReadAll(r.Body)` (the modern replacement
                      # for `ioutil.ReadAll`) to parse request bodies —
                      # neither was previously surfaced.
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

      resolve_public_dirs(public_dirs)

      result
    end

    def get_method_from_line(line : String) : String
      # Extract method from .Methods("GET", "POST") or default to GET
      if match = line.match(/\.Methods\(\s*[\"']([^\"']+)[\"']/)
        match[1].upcase
      else
        "GET"
      end
    end

    def get_param(line : String, pattern : String, endpoint : Endpoint? = nil) : Param
      param_name = ""
      param_type = ""

      # Special handling for different patterns
      case pattern
      when "Vars"
        # Handle mux.Vars(r)["id"] pattern
        if match = line.match(/Vars\([^)]+\)\s*\[\s*[\"']([^\"']+)[\"']\s*\]/)
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
          param_type = form_value_param_type(endpoint)
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
