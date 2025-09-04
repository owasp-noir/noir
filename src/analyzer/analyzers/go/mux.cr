require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Mux < Analyzer
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      subrouters = [] of Hash(String, String)
      channel = Channel(String).new
      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path) && File.extname(path) == ".go"
                    # Read all lines for lookahead processing
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      lexer = GolangLexer.new

                      # Handle subrouter creation (e.g., r.PathPrefix("/api/").Subrouter())
                      if line.includes?(".PathPrefix(") && line.includes?(".Subrouter()")
                        map = lexer.tokenize(line)
                        before = Token.new(:unknown, "", 0)
                        subrouter_name = ""
                        subrouter_path = ""
                        map.each do |token|
                          if token.type == :assign
                            subrouter_name = before.value.to_s.gsub(":", "").gsub(/\s/, "")
                          end

                          if token.type == :string
                            subrouter_path = token.value.to_s
                            subrouters.each do |sub|
                              sub.each do |key, value|
                                if before.value.to_s.includes? key
                                  subrouter_path = value + subrouter_path
                                end
                              end
                            end
                          end

                          before = token
                        end

                        if subrouter_name.size > 0 && subrouter_path.size > 0
                          subrouters << {subrouter_name => subrouter_path}
                        end
                      end

                      # Handle route definitions (e.g., r.HandleFunc("/path", handler).Methods("GET"))
                      if line.includes?(".HandleFunc(")
                        get_route_path(line, subrouters).tap do |route_path|
                          if route_path.size > 0
                            # Check next 5 lines for .Methods() call
                            method = "GET" # default
                            (0..5).each do |lookahead|
                              check_line_idx = index + lookahead
                              break if check_line_idx >= lines.size
                              check_line = lines[check_line_idx]
                              if check_line.includes?(".Methods(")
                                method = get_method_from_line(check_line)
                                break
                              end
                            end

                            new_endpoint = Endpoint.new("#{route_path}", method, details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      # Handle parameter extraction patterns in Go (order matters - check more specific patterns first)
                      if line.includes?("Vars(")
                        get_param(line, "Vars").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      elsif line.includes?("Query().Get(")
                        get_param(line, "Query").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      elsif line.includes?("PostFormValue(")
                        get_param(line, "PostFormValue").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      elsif line.includes?("FormValue(")
                        get_param(line, "FormValue").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      elsif line.includes?("Header.Get(")
                        get_param(line, "Header").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      elsif line.includes?("Cookie(")
                        get_param(line, "Cookie").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      end

                      # Handle static file serving (e.g., r.PathPrefix("/static/").Handler(...))
                      if line.includes?(".PathPrefix(") && line.includes?(".Handler(") && !line.includes?(".Subrouter(")
                        get_static_path(line).tap do |static_path|
                          if static_path["static_path"].size > 0 && static_path["file_path"].size > 0
                            public_dirs << static_path
                          end
                        end
                      end
                    end
                  end
                rescue e
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

    def get_route_path(line : String, subrouters : Array(Hash(String, String))) : String
      lexer = GolangLexer.new
      map = lexer.tokenize(line)
      before = Token.new(:unknown, "", 0)
      map.each do |token|
        if token.type == :string
          final_path = token.value.to_s
          subrouters.each do |sub|
            sub.each do |key, value|
              if before.value.to_s.includes? key
                final_path = value + final_path
              end
            end
          end

          return final_path
        end

        before = token
      end

      ""
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

    def get_static_path(line : String) : Hash(String, String)
      static_path = ""
      file_path = ""

      # Handle r.PathPrefix("/static/").Handler(...) pattern
      if match = line.match(/PathPrefix\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
        static_path = match[1]
      end

      # Extract file path from http.Dir("./static/") pattern
      if match = line.match(/http\.Dir\s*\(\s*[\"']([^\"']+)[\"']\s*\)/)
        file_path = match[1]
        # Remove leading ./ if present
        file_path = file_path.gsub(/^\.\//, "")
      end

      {
        "static_path" => static_path,
        "file_path"   => file_path,
      }
    end
  end
end
