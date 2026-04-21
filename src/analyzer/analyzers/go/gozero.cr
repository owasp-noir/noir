require "../../engines/go_engine"

module Analyzer::Go
  class GoZero < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      groups = [] of Hash(String, String)
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

                  # Handle both .go files and .api files
                  if File.exists?(path) && (File.extname(path) == ".go" || File.extname(path) == ".api")
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      last_endpoint = Endpoint.new("", "")
                      file.each_line.with_index do |line, index|
                        details = Details.new(PathInfo.new(path, index + 1))

                        # Handle .api files (go-zero API definition files)
                        if File.extname(path) == ".api"
                          # Parse go-zero .api route definitions
                          # Format: get /users/:id (GetUserById)
                          # Format: post /users (CreateUser)
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
                          lexer = GolangLexer.new

                          # Handle group routing (similar to Gin)
                          analyze_group(line, lexer, groups)

                          # Handle HTTP method routing
                          # go-zero typically uses patterns like: server.Get("/path", handler)
                          # or router methods like .GET(), .POST(), etc.
                          if line.includes?(".Get(") || line.includes?(".Post(") || line.includes?(".Put(") || line.includes?(".Delete(") ||
                             line.includes?(".GET(") || line.includes?(".POST(") || line.includes?(".PUT(") || line.includes?(".DELETE(") ||
                             line.includes?(".Patch(") || line.includes?(".PATCH(") || line.includes?(".Head(") || line.includes?(".HEAD(") ||
                             line.includes?(".Options(") || line.includes?(".OPTIONS(")
                            get_route_path(line, groups).tap do |resolved_route_path|
                              if resolved_route_path.size > 0
                                # Extract method from the line (e.g., ".Get(" -> "GET")
                                method_match = line.match(/\.(Get|Post|Put|Delete|Patch|Head|Options|GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\(/)
                                if method_match
                                  method = method_match[1].upcase
                                  new_endpoint = Endpoint.new("#{resolved_route_path}", method, details)
                                  result << new_endpoint
                                  last_endpoint = new_endpoint
                                end
                              end
                            end
                          end

                          # Handle parameter extraction patterns common in go-zero
                          ["Query", "PostForm", "GetHeader", "PathParam", "FormValue"].each do |pattern|
                            if line.includes?("#{pattern}(")
                              add_param_to_endpoint(get_param(line), last_endpoint)
                            end
                          end

                          # Handle static file serving
                          if line.includes?("Static(")
                            add_static_path_if_valid(get_static_path(line), public_dirs)
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

    def get_static_path(line : String) : Hash(String, String)
      # Extract static path configuration from go-zero static serving
      # e.g., router.Static("/static", "./public")
      if match = line.match(/Static\s*\(\s*\"([^"]+)\"\s*,\s*\"([^"]+)\"/)
        static_path = match[1]
        file_path = match[2].gsub("\"", "").gsub(" ", "").gsub(")", "")
        return {
          "static_path" => static_path,
          "file_path"   => file_path,
        }
      end

      {
        "static_path" => "",
        "file_path"   => "",
      }
    end
  end
end
