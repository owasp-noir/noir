require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
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
                  prefix_stack = [] of String
                  last_endpoint = Endpoint.new("", "")
                  in_inline_handler = false
                  handler_brace_count = 0

                  lines.each_with_index do |line, index|
                    details = Details.new(PathInfo.new(path, index + 1))

                    # Mount 처리: 객체가 무엇이든 Mount 호출 인식
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

                    # Route 블록 처리: 객체가 무엇이든 Route 호출 인식 (접두사 저장)
                    if line.includes?(".Route(")
                      if match = line.match(/[a-zA-Z]\w*\.Route\(\s*"([^"]+)"/)
                        prefix_stack << match[1]
                      end
                      next
                    end

                    # 블록 종료 시 접두사 제거 (}로 시작하는 줄 또는 })로 끝나는 줄 처리)
                    # Closing braces that end Route blocks
                    if (line.strip == "}" || line.strip == "})") && !prefix_stack.empty?
                      prefix_stack.pop
                      next
                    end

                    # 실제 endpoint 처리: .Get, .Post, .Put, .Delete (임의 객체)
                    # Skip if it's a Header.Get, Cookie, or other parameter extraction pattern
                    if !line.includes?("Header.Get") && !line.includes?("Cookie(") &&
                       !line.includes?("URLParam") && !line.includes?("Query().Get") &&
                       !line.includes?("FormValue(") && !line.includes?("PostFormValue(")
                      method = ""
                      route_path = ""

                      # First try to match method with route on same line
                      # Route path must start with "/" to be a valid HTTP endpoint
                      if match = line.match(/[a-zA-Z]\w*\.(GET|Get|get|POST|Post|post|PUT|Put|put|DELETE|Delete|delete|PATCH|Patch|patch)\(\s*"(\/[^"]*)"/i)
                        method = match[1].upcase
                        route_path = match[2]
                        # Then try to match method without route (for multi-line cases)
                      elsif match = line.match(/[a-zA-Z]\w*\.(GET|Get|get|POST|Post|post|PUT|Put|put|DELETE|Delete|delete|PATCH|Patch|patch)\s*\(/i)
                        method = match[1].upcase
                        # Look for route in next line - must start with "/" to be valid
                        if index + 1 < lines.size
                          next_line = lines[index + 1]
                          if next_match = next_line.match(/"(\/[^"]*)"/)
                            route_path = next_match[1]
                          end
                        end
                      end

                      if method.size > 0 && route_path.size > 0
                        full_route = prefix_stack.join("") + route_path
                        new_endpoint = Endpoint.new(full_route, method, details)
                        result << new_endpoint
                        last_endpoint = new_endpoint

                        # Check if this route has an inline handler (func keyword after the route)
                        if line.includes?("func(")
                          in_inline_handler = true
                          handler_brace_count = line.count("{") - line.count("}")
                        end
                      end
                    end

                    # Track brace count when inside an inline handler
                    if in_inline_handler
                      handler_brace_count += line.count("{")
                      handler_brace_count -= line.count("}")

                      # End of inline handler
                      if handler_brace_count <= 0
                        in_inline_handler = false
                        handler_brace_count = 0
                      end
                    end

                    # Parameter extraction patterns (order matters - check more specific patterns first)
                    # Extract chi.URLParam only in inline handler or in ArticleCtx-like middleware
                    # Other parameters only in inline handler context
                    if line.includes?("chi.URLParam(")
                      # Only extract URLParam if in inline handler, or it's part of a middleware function
                      if in_inline_handler
                        get_param(line, "URLParam").tap do |param|
                          if param.name.size > 0 && last_endpoint.url != ""
                            last_endpoint.params << param
                          end
                        end
                      end
                    elsif in_inline_handler
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
              rescue e : File::NotFoundError
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
      content = File.read(file_path)
      if content.includes?("func #{func_name}(")
        block_started = false
        brace_count = 0
        content.each_line do |line|
          if !block_started
            if line.includes?("func #{func_name}(")
              block_started = true
              if line.includes?("{")
                brace_count += 1
              end
            end
            next
          else
            brace_count += line.count("{")
            brace_count -= line.count("}")
            details = Details.new(PathInfo.new(file_path))
            method = ""
            route_path = ""
            # Support case-insensitive method names
            # Route path must start with "/" to be a valid HTTP endpoint
            if match = line.match(/[a-zA-Z]\w*\.(GET|Get|get|POST|Post|post|PUT|Put|put|DELETE|Delete|delete|PATCH|Patch|patch)\(\s*"(\/[^"]*)"/i)
              method = match[1].upcase
              route_path = match[2]
            end

            if method.size > 0 && route_path.size > 0
              endpoints << Endpoint.new(route_path, method, details)
            end

            break if brace_count <= 0
          end
        end
      end
      endpoints
    end
  end
end
