require "./common"

module Analyzer::Go
  class Gf < Common
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      groups = [] of Hash(String, String)
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
                    # Read all lines for multi-line pattern support
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    # Track closure-style groups with brace depth
                    closure_groups = [] of Tuple(String, Int32)
                    brace_depth = 0

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))
                      lexer = GolangLexer.new

                      # Update brace depth
                      brace_depth += line.count('{') - line.count('}')

                      # Pop closure groups whose scope has ended
                      while closure_groups.size > 0 && brace_depth < closure_groups.last[1]
                        closure_groups.pop
                      end

                      current_closure_prefix = closure_groups.size > 0 ? closure_groups.last[0] : ""

                      # Detect closure-style group: s.Group("/api", func(group *ghttp.RouterGroup) {
                      if line.includes?(".Group(") && line.includes?("func(")
                        if str_match = line.match(/\.Group\(\s*"([^"]*)"/)
                          new_prefix = current_closure_prefix + str_match[1]
                          closure_groups << {new_prefix, brace_depth}
                        end
                      end

                      # Handle variable-assigned groups via common analyze_group
                      analyze_group(line, lexer, groups)

                      if line.includes?(".BindHandler(") || line.includes?(".BindMiddleware(")
                        get_route_path(line, groups).tap do |route_path|
                          if route_path.size > 0
                            full_path = current_closure_prefix + route_path
                            new_endpoint = Endpoint.new(full_path, "ALL", details)
                            result << new_endpoint
                            last_endpoint = new_endpoint
                          end
                        end
                      end

                      # Exclude logger matches or variable assignments like err = ... or info := ...
                      if !line.includes?("logger.") && (match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|TRACE|ALL)\s*\(/i))
                        method = match[1].upcase

                        if line.includes?(".Group(") && !line.includes?("func(")
                          # Chained group+method: s.Group("/multi").GET("/line", ...)
                          if group_match = line.match(/\.Group\(\s*"([^"]*)"/)
                            chain_prefix = current_closure_prefix + group_match[1]
                            tokens = lexer.tokenize(line)
                            path_strings = tokens.select { |t| t.type == :string && t.value.to_s.starts_with?("/") }
                            route_path = ""
                            if path_strings.size >= 2
                              route_path = chain_prefix + path_strings[1].value.to_s
                            elsif index + 1 < lines.size
                              next_route = get_route_path(lines[index + 1], [] of Hash(String, String))
                              if next_route.size > 0
                                route_path = chain_prefix + next_route
                              end
                            end
                            if route_path.size > 0
                              new_endpoint = Endpoint.new(route_path, method, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          end
                        else
                          # Normal route
                          get_route_path(line, groups).tap do |rpath|
                            # Handle multi-line routes - check next lines if route is empty
                            if rpath.size == 0 && index + 1 < lines.size
                              next_line = lines[index + 1]
                              rpath = get_route_path(next_line, groups)
                            end

                            if rpath.size > 0
                              full_path = current_closure_prefix + rpath
                              new_endpoint = Endpoint.new(full_path, method, details)
                              result << new_endpoint
                              last_endpoint = new_endpoint
                            end
                          end
                        end
                      end

                      ["Get", "GetQuery", "GetForm", "GetHeader", "GetUploadFile"].each do |pattern|
                        if line.includes?("#{pattern}(") && !line.includes?("Cookie.Get")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      if line.includes?("Static(")
                        add_static_path_if_valid(get_static_path(line), public_dirs)
                      end

                      if line.includes?("Cookie.Get(")
                        match = line.match(/Cookie\.Get\(\"(.*)\"\)/)
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
      param_type =
        if line.includes?("GetQuery(")
          "query"
        elsif line.includes?("GetForm(") || line.includes?("GetUploadFile(")
          "form"
        elsif line.includes?("GetHeader(")
          "header"
        else
          "json"
        end

      match = line.match(/\(\s*"([^"]+)"\s*\)/)
      if match
        return Param.new(match[1], "", param_type)
      end

      Param.new("", "", "")
    end
  end
end
