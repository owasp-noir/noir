require "../../../models/analyzer"

module Analyzer::Rust
  class ActixWeb < Analyzer
    def analyze
      # Source Analysis
      pattern = /#\[(get|post|put|delete|patch)\("([^"]+)"\)\]/
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

                  if File.exists?(path) && File.extname(path) == ".rs"
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    lines.each_with_index do |line, index|
                        if line.to_s.includes? "#["
                          match = line.match(pattern)
                          if match
                            begin
                              route_argument = match[2]
                              callback_argument = match[1]
                              details = Details.new(PathInfo.new(path, index + 1))
                              endpoint = Endpoint.new("#{route_argument}", callback_to_method(callback_argument), details)
                              
                              # Extract path parameters from route pattern
                              extract_path_params(route_argument, endpoint)
                              
                              # Look ahead to extract parameters from function signature and body
                              extract_function_params(lines, index + 1, endpoint)
                              
                              result << endpoint
                            rescue e
                              logger.debug "Error processing endpoint: #{e.message}"
                            end
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
      end

      result
    end

    def callback_to_method(str)
      method = str.split("(").first
      if !["get", "post", "put", "delete", "patch"].includes?(method)
        method = "get"
      end

      method.upcase
    end

    # Extract path parameters from the route pattern like /users/{id}
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/\{(\w+)\}/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract parameters from function signature and body
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      # Look ahead up to 20 lines for the function definition and body
      in_function = false
      brace_count = 0
      seen_opening_brace = false
      
      (start_index...[start_index + 20, lines.size].min).each do |i|
        line = lines[i]
        
        # Track if we're inside the function
        if line.includes?("async fn ") || line.includes?("fn ")
          in_function = true
        end
        
        # Track braces to know when function ends
        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')
        
        # Extract query parameters from web::Query<T>
        if line.includes?("web::Query<") || line.includes?(": web::Query")
          endpoint.push_param(Param.new("query", "", "query"))
        end
        
        # Extract JSON body from web::Json<T>
        if line.includes?("web::Json<") || line.includes?(": web::Json")
          endpoint.push_param(Param.new("body", "", "json"))
        end
        
        # Extract form body from web::Form<T>
        if line.includes?("web::Form<") || line.includes?(": web::Form")
          endpoint.push_param(Param.new("form", "", "form"))
        end
        
        # Extract headers from .headers().get()
        if line.includes?(".headers().get(")
          match = line.match(/\.headers\(\)\.get\("([^"]+)"\)/)
          if match
            header_name = match[1]
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end
        
        # Extract cookies from .cookie()
        if line.includes?(".cookie(")
          match = line.match(/\.cookie\("([^"]+)"\)/)
          if match
            cookie_name = match[1]
            endpoint.push_param(Param.new(cookie_name, "", "cookie"))
          end
        end
        
        # Stop if we've moved past the function (brace count is back to 0 after we've seen an opening brace)
        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end
        
        # Also stop if we hit another attribute
        if i > start_index && line.strip.starts_with?("#[")
          break
        end
      end
    end
  end
end
