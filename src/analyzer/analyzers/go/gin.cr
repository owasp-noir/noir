require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Gin < Analyzer
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
                  if File.exists?(path) && File.extname(path) == ".go"
                    # Read all lines for multi-line pattern support
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")
                    
                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      lexer = GolangLexer.new

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

                        # Use case-insensitive regex for HTTP method detection
                        # Matches patterns like: .GET(, .Get(, .get(, .POST(, .Post(, .post(, etc.
                        # Exclude parameter extraction patterns like Header.Get(, Cookie.Get(, etc.
                        if !line.includes?("Header.Get") && !line.includes?("Cookie.Get") &&
                           (match = line.match(/\.(GET|Get|get|POST|Post|post|PUT|Put|put|DELETE|Delete|delete|PATCH|Patch|patch|OPTIONS|Options|options|HEAD|Head|head)\s*\(/i))
                          method = match[1].upcase
                          get_route_path(line, groups).tap do |route_path|
                            # Handle multi-line routes - check next lines if route is empty
                            if route_path.size == 0 && index + 1 < lines.size
                              next_line = lines[index + 1]
                              route_path = get_route_path(next_line, groups)
                            end
                            
                            if route_path.size > 0
                              new_endpoint = Endpoint.new("#{route_path}", method, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          end
                        end

                        ["Query", "PostForm", "GetHeader"].each do |pattern|
                          if line.includes?("#{pattern}(")
                            get_param(line).tap do |param|
                              if param.name.size > 0 && last_endpoint.method != ""
                                last_endpoint.params << param
                              end
                            end
                          end
                        end

                        if line.includes?("Static(")
                          get_static_path(line).tap do |static_path|
                            if static_path["static_path"].size > 0 && static_path["file_path"].size > 0
                              public_dirs << static_path
                            end
                          end
                        end

                        if line.includes?("Cookie(")
                          match = line.match(/Cookie\(\"(.*)\"\)/)
                          if match
                            cookie_name = match[1]
                            last_endpoint.params << Param.new(cookie_name, "", "cookie")
                          end
                        end
                      end
                  end
                rescue e : File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      public_dirs.each do |p_dir|
        full_path = (base_path + "/" + p_dir["file_path"]).gsub_repeatedly("//", "/")
        get_files_by_prefix(full_path).each do |path|
          if File.exists?(path)
            if p_dir["static_path"].ends_with?("/")
              p_dir["static_path"] = p_dir["static_path"][0..-2]
            end

            details = Details.new(PathInfo.new(path))
            result << Endpoint.new("#{p_dir["static_path"]}#{path.gsub(full_path, "")}", "GET", details)
          end
        end
      end

      result
    end

    def get_param(line : String) : Param
      param_type = "json"
      if line.includes?("Query(")
        param_type = "query"
      end
      if line.includes?("PostForm(")
        param_type = "form"
      end
      if line.includes?("GetHeader(")
        param_type = "header"
      end

      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(")")
        if second.size > 1
          if line.includes?("DefaultQuery") || line.includes?("DefaultPostForm")
            param_name = second[0].split(",")[0].gsub("\"", "")
            rtn = Param.new(param_name, "", param_type)
          else
            param_name = second[0].gsub("\"", "")
            rtn = Param.new(param_name, "", param_type)
          end

          return rtn
        end
      end

      Param.new("", "", "")
    end

    def get_static_path(line : String) : Hash(String, String)
      first = line.strip.split("(")
      if first.size > 1
        second = first[1].split(",")
        if second.size > 1
          static_path = second[0].gsub("\"", "")
          file_path = second[1].gsub("\"", "").gsub(" ", "").gsub(")", "")
          rtn = {
            "static_path" => static_path,
            "file_path"   => file_path,
          }

          return rtn
        end
      end

      {
        "static_path" => "",
        "file_path"   => "",
      }
    end

    def get_route_path(line : String, groups : Array(Hash(String, String))) : String
      lexer = GolangLexer.new
      map = lexer.tokenize(line)
      before = Token.new(:unknown, "", 0)
      map.each do |token|
        if token.type == :string
          final_path = token.value.to_s
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
  end
end
