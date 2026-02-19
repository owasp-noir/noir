require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  private class ChiRouteState
    property prefix_stack : Array(String) = [] of String
    property? in_inline_handler : Bool = false
    property handler_brace_count : Int32 = 0
  end

  class Chi < Analyzer
    def analyze
      result = [] of Endpoint
      channel = Channel(String).new
      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                path = channel.receive?
                break if path.nil?
                next if File.directory?(path)
                if File.exists?(path) && File.extname(path) == ".go"
                  # Read all lines for multi-line pattern support
                  lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                  state = ChiRouteState.new
                  last_endpoint = Endpoint.new("", "")

                  # Pre-scan: collect mounted function names to skip their bodies
                  mounted_functions = Set(String).new
                  lines.each do |scan_line|
                    if scan_line.includes?(".Mount(")
                      if scan_match = scan_line.match(/[a-zA-Z]\w*\.Mount\(\s*"([^"]+)"\s*,\s*([^(]+)\(\)/)
                        mounted_functions << scan_match[2].strip
                      end
                    end
                  end
                  in_mounted_func = false
                  mounted_func_brace_count = 0

                  lines.each_with_index do |line, index|
                    # Skip bodies of mounted router functions (already handled by analyze_router_function)
                    if in_mounted_func
                      mounted_func_brace_count += line.count("{")
                      mounted_func_brace_count -= line.count("}")
                      if mounted_func_brace_count <= 0
                        in_mounted_func = false
                      end
                      next
                    end
                    if !mounted_functions.empty? && line.strip.starts_with?("func ")
                      if func_match = line.match(/func\s+([a-zA-Z_]\w*)\s*\(/)
                        if mounted_functions.includes?(func_match[1])
                          in_mounted_func = true
                          mounted_func_brace_count = line.count("{") - line.count("}")
                          if mounted_func_brace_count <= 0
                            in_mounted_func = false
                          end
                          next
                        end
                      end
                    end

                    details = Details.new(PathInfo.new(path, index + 1))

                    # Mount handling (unique to analyze)
                    if line.includes?(".Mount(")
                      if match = line.match(/[a-zA-Z]\w*\.Mount\(\s*"([^"]+)"\s*,\s*([^(]+)\(\)/)
                        mount_prefix = match[1]
                        router_function = match[2]
                        endpoints = analyze_router_function(path, router_function)
                        endpoints.each do |ep|
                          ep.url = mount_prefix + ep.url
                          result << ep
                        end
                      end
                      next
                    end

                    next_line = index + 1 < lines.size ? lines[index + 1] : nil
                    endpoint, handled = process_route_line(line, next_line, state, details)
                    next if handled

                    if endpoint
                      result << endpoint
                      last_endpoint = endpoint
                    end

                    # Parameter extraction patterns (order matters - check more specific patterns first)
                    # Extract chi.URLParam only in inline handler or in ArticleCtx-like middleware
                    # Other parameters only in inline handler context
                    if line.includes?("chi.URLParam(")
                      # Only extract URLParam if in inline handler, or it's part of a middleware function
                      if state.in_inline_handler?
                        get_param(line, "URLParam").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      end
                    elsif state.in_inline_handler?
                      if line.includes?("Query().Get(")
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
                    end
                  end
                end
              rescue File::NotFoundError
                logger.debug "File not found: #{path}"
              end
            end
          end
        end
      rescue e
        logger.debug e
      end
      result
    end

    private def process_route_line(line : String, next_line : String?,
                                   state : ChiRouteState, details : Details) : {Endpoint?, Bool}
      endpoint = nil
      handled = false
      handler_initialized_this_line = false

      # Group block: push empty prefix
      if line.includes?(".Group(")
        state.prefix_stack << ""
        handled = true
        # Route block: push path prefix
      elsif line.includes?(".Route(")
        if match = line.match(/[a-zA-Z]\w*\.Route\(\s*"([^"]+)"/)
          state.prefix_stack << match[1]
        end
        handled = true
        # Closing brace: pop prefix if applicable (skip when inside inline handler)
      elsif (line.strip == "}" || line.strip == "})") && !state.prefix_stack.empty? && !state.in_inline_handler?
        state.prefix_stack.pop
        handled = true
      else
        # Endpoint detection
        method = ""
        route_path = ""
        # Route path must start with "/" to be a valid HTTP endpoint
        if match = line.match(/[a-zA-Z]\w*\.(GET|POST|PUT|DELETE|PATCH)\(\s*"(\/[^"]*)"/i)
          method = match[1].upcase
          route_path = match[2]
        elsif match = line.match(/[a-zA-Z]\w*\.(GET|POST|PUT|DELETE|PATCH)\s*\(/i)
          method = match[1].upcase
          if next_line
            if next_match = next_line.match(/"(\/[^"]*)"/)
              route_path = next_match[1]
            end
          end
        end

        if method.size > 0 && route_path.size > 0
          full_route = state.prefix_stack.join("") + route_path
          endpoint = Endpoint.new(full_route, method, details)

          # Check if this route has an inline handler
          if line.includes?("func(")
            state.in_inline_handler = true
            state.handler_brace_count = line.count("{") - line.count("}")
            handler_initialized_this_line = true
            if state.handler_brace_count <= 0
              state.in_inline_handler = false
              state.handler_brace_count = 0
            end
          end
        end
      end

      # Track inline handler braces (skip line where handler was just initialized)
      if state.in_inline_handler? && !handler_initialized_this_line
        state.handler_brace_count += line.count("{")
        state.handler_brace_count -= line.count("}")
        if state.handler_brace_count <= 0
          state.in_inline_handler = false
          state.handler_brace_count = 0
        end
      end

      {endpoint, handled}
    end

    def get_param(line : String, pattern : String) : Param
      param_name = ""
      param_type = ""

      # Special handling for different patterns
      case pattern
      when "URLParam"
        # Handle chi.URLParam(r, "id") pattern
        if match = line.match(/chi\.URLParam\([^,]+,\s*[\"']([^\"']+)[\"']\s*\)/)
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
          param_type = "form"
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

    # 추출: 객체.메서드("경로", ...) 형태에서 경로 추출
    def extract_route_path(line : String) : String
      if match = line.match(/[a-zA-Z]\w*\.\w+\(\s*"([^"]+)"/)
        return match[1]
      end
      ""
    end

    # 주어진 파일 내에 정의된 router 함수의 내용을 추출하여 엔드포인트 정보로 변환
    def analyze_router_function(file_path : String, func_name : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(file_path, encoding: "utf-8", invalid: :skip)

      # Find function start
      func_start = -1
      lines.each_with_index do |line, i|
        if line.includes?("func #{func_name}(")
          func_start = i
          break
        end
      end
      return endpoints if func_start < 0

      brace_count = 0
      state = ChiRouteState.new
      started = false

      (func_start...lines.size).each do |index|
        line = lines[index]

        if !started
          started = true
          brace_count += 1 if line.includes?("{")
          next
        end

        brace_count += line.count("{")
        brace_count -= line.count("}")

        next_line = index + 1 < lines.size ? lines[index + 1] : nil
        details = Details.new(PathInfo.new(file_path))
        endpoint, _ = process_route_line(line, next_line, state, details)
        endpoints << endpoint if endpoint

        break if brace_count <= 0
      end

      endpoints
    end
  end
end
