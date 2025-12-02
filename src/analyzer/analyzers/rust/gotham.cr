require "../../../models/analyzer"

module Analyzer::Rust
  class Gotham < Analyzer
    # Maximum lines to look ahead for handler name
    MAX_HANDLER_LOOKUP_LINES = 5

    def analyze
      # Source Analysis for Gotham web framework
      # Gotham uses builder pattern: Router::builder().get("/path").to(handler)
      # Route paths must start with /
      pattern = /\.(get|post|put|delete|patch|head|options)\s*\(\s*"(\/[^"]*)"\s*\)/
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
                      # Look for Gotham routing patterns like .get("/path")
                      if line.includes?(".") && (line.includes?("get") || line.includes?("post") ||
                         line.includes?("put") || line.includes?("delete") ||
                         line.includes?("patch") || line.includes?("head") ||
                         line.includes?("options"))
                        match = line.match(pattern)
                        if match
                          begin
                            method = match[1]
                            route_path = match[2]

                            # Parse path parameters (Gotham uses :param syntax)
                            params = [] of Param
                            final_path = route_path.gsub(/:(\w+)/) do |param_match|
                              param_name = param_match[1..-1] # Remove the ':'
                              params << Param.new(param_name, "", "path")
                              ":#{param_name}"
                            end

                            details = Details.new(PathInfo.new(path, index + 1))
                            endpoint = Endpoint.new(final_path, method.upcase, details)
                            params.each do |param|
                              endpoint.push_param(param)
                            end

                            # Try to find the handler function and extract cookies/headers
                            # Look for .to(handler_name) in nearby lines
                            handler_name = find_handler_name(lines, index)
                            if handler_name
                              extract_handler_params(lines, handler_name, endpoint)
                            end

                            result << endpoint
                          rescue
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

    # Find the handler function name from .to(handler) pattern
    private def find_handler_name(lines : Array(String), start_index : Int32) : String?
      (start_index...[start_index + MAX_HANDLER_LOOKUP_LINES, lines.size].min).each do |i|
        line = lines[i]
        match = line.match(/\.to\s*\(\s*(\w+)\s*\)/)
        if match
          return match[1]
        end
      end
      nil
    end

    # Extract cookies and headers from the handler function body
    private def extract_handler_params(lines : Array(String), handler_name : String, endpoint : Endpoint)
      in_function = false
      brace_count = 0
      seen_opening_brace = false

      lines.each_with_index do |line, _|
        # Find the handler function definition
        if !in_function && line.includes?("fn #{handler_name}")
          in_function = true
        end

        next unless in_function

        # Track braces
        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        # Extract cookies from .cookie() or cookies().get() patterns
        if line.includes?(".cookie(")
          match = line.match(/\.cookie\s*\(\s*"([^"]+)"\s*\)/)
          if match
            cookie_name = match[1]
            unless endpoint.params.any? { |p| p.name == cookie_name && p.param_type == "cookie" }
              endpoint.push_param(Param.new(cookie_name, "", "cookie"))
            end
          end
        end

        # Extract headers from .headers().get() or HeaderMap access
        if line.includes?(".headers()") && line.includes?(".get(")
          match = line.match(/\.headers\(\)\s*\.get\s*\(\s*"([^"]+)"\s*\)/)
          if match
            header_name = match[1]
            unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end
        end

        # Extract headers using header::XXX patterns (Gotham-style)
        if line.includes?("header::")
          match = line.match(/header::(\w+)/)
          if match
            header_name = match[1].gsub("_", "-")
            unless endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
          end
        end

        # Stop if we've moved past the function
        if seen_opening_brace && brace_count == 0
          break
        end
      end
    end
  end
end
