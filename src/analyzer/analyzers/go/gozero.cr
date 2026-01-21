require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class GoZero < Analyzer
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      groups = [] of Hash(String, String)
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
                          if line.includes?(".Group(")
                            map = lexer.tokenize(line)
                            before = Token.new(:unknown, "", 0)
                            group_name = ""
                            group_path = ""
                            map.each do |token|
                              if token.type == :assign
                                group_name = before.value.to_s.gsub(":", "").gsub(/\s/, "")
                              end

                              if token.type == :string
                                group_path = token.value.to_s
                                groups.each do |group|
                                  group.each do |key, value|
                                    if before.value.to_s.includes? key
                                      group_path = value + group_path
                                    end
                                  end
                                end
                              end

                              before = token
                            end

                            if group_name.size > 0 && group_path.size > 0
                              groups << {
                                group_name => group_path,
                              }
                            end
                          end

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
                              get_param(line).tap do |param|
                                if param.name.size > 0 && last_endpoint.method != ""
                                  last_endpoint.params << param
                                end
                              end
                            end
                          end

                          # Handle static file serving
                          if line.includes?("Static(")
                            get_static_path(line).tap do |p_dir|
                              if p_dir["static_path"].size > 0 && p_dir["file_path"].size > 0
                                public_dirs << p_dir
                              end
                            end
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
        # Handle channel errors
      end

      # Process static files
      public_dirs.each do |p_dir|
        full_path = File.expand_path(p_dir["file_path"], @base_path)
        if File.directory?(full_path)
          Dir.glob("#{escape_glob_path(full_path)}/**/*") do |path|
            next if File.directory?(path)
            if File.exists?(path)
              if p_dir["static_path"].ends_with?("/")
                p_dir["static_path"] = p_dir["static_path"][0..-2]
              end

              details = Details.new(PathInfo.new(path))
              result << Endpoint.new("#{p_dir["static_path"]}#{path.gsub(full_path, "")}", "GET", details)
            end
          end
        end
      end

      result
    end

    def get_route_path(line : String, groups : Array(Hash(String, String))) : String
      lexer = GolangLexer.new
      map = lexer.tokenize(line)
      before = Token.new(:unknown, "", 0)
      map.each do |token|
        if token.type == :string
          final_path = token.value.to_s
          # Route path must start with "/" to be a valid HTTP endpoint
          next unless final_path.starts_with?("/")
          groups.each do |group|
            group.each do |key, value|
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
