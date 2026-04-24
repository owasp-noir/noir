require "../../engines/go_engine"

module Analyzer::Go
  class Mux < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      # Mux subrouters are created via the two-call chain
      # `api := r.PathPrefix("/api/").Subrouter()`. The engine fixpoint
      # treats "Subrouter" as the grouping method and peeks through the
      # chain to read the PathPrefix argument.
      package_groups, file_contents = collect_package_groups_ts("Subrouter")
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
                    content = file_contents[path]? || File.read(path, encoding: "utf-8", invalid: :skip)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    cross_file_groups = ts_groups_for_directory(package_groups, File.dirname(path))
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

                    # Mux static-file: `r.PathPrefix("/x/").Handler(... http.Dir("./x/") ...)`
                    Noir::TreeSitterGoRouteExtractor.extract_mux_statics(content).each do |sp|
                      public_dirs << {"static_path" => sp.url_prefix, "file_path" => sp.disk_path}
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          new_endpoint = Endpoint.new(route.path, route.verb, details)
                          # mux's `.Queries("type", "{type}", ...)` declares
                          # required query params; bind them to the endpoint.
                          route.query_params.each do |qp|
                            new_endpoint.params << Param.new(qp, "", "query")
                          end
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      # Handle parameter extraction patterns in Go (order matters - check more specific patterns first)
                      if line.includes?("Vars(")
                        add_param_to_endpoint(get_param(line, "Vars"), last_endpoint)
                      elsif line.includes?("Query().Get(")
                        add_param_to_endpoint(get_param(line, "Query"), last_endpoint)
                      elsif line.includes?("PostFormValue(")
                        add_param_to_endpoint(get_param(line, "PostFormValue"), last_endpoint)
                      elsif line.includes?("FormValue(")
                        add_param_to_endpoint(get_param(line, "FormValue"), last_endpoint)
                      elsif line.includes?("Header.Get(")
                        add_param_to_endpoint(get_param(line, "Header"), last_endpoint)
                      elsif line.includes?("Cookie(")
                        add_param_to_endpoint(get_param(line, "Cookie"), last_endpoint)
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

      # Process static files
      public_dirs.each do |p_dir|
        full_path = (base_path + "/" + p_dir["file_path"]).gsub_repeatedly("//", "/")
        get_files_by_prefix(full_path).each do |path|
          if File.exists?(path)
            static_path = p_dir["static_path"]
            if static_path.ends_with?("/")
              static_path = static_path[0..-2]
            end

            file_relative_path = path.gsub(full_path, "")
            if !file_relative_path.starts_with?("/")
              file_relative_path = "/" + file_relative_path
            end

            details = Details.new(PathInfo.new(path))
            result << Endpoint.new("#{static_path}#{file_relative_path}", "GET", details)
          end
        end
      end

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

    def get_param(line : String, pattern : String) : Param
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
          param_type = "query"
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
  end
end
