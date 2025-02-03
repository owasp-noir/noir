require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Chi < Analyzer
    def analyze
      result = [] of Endpoint
      channel = Channel(String).new
      begin
        spawn do
          Dir.glob("#{@base_path}/**/*") do |file|
            channel.send(file)
          end
          channel.close
        end

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                path = channel.receive?
                break if path.nil?
                next if File.directory?(path)
                if File.exists?(path) && File.extname(path) == ".go"
                  File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                    prefix_stack = [] of String
                    file.each_line.with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Mount 처리: r.Mount("/prefix", mountedFunc())
                      if line.includes?("r.Mount(")
                        if match = line.match(/r\.Mount\(\s*"([^"]+)"\s*,\s*([^(]+)\(\)/)
                          mount_prefix = match[1]
                          router_function = match[2]
                          # mount된 라우터 함수 내의 엔드포인트를 분석해서 mount prefix를 붙임
                          endpoints = analyze_router_function(path, router_function)
                          endpoints.each do |ep|
                            ep.url = mount_prefix + ep.url
                            result << ep
                          end
                        end
                        next
                      end

                      # Route 블록 처리: 블록 내 접두사 저장
                      if line.includes?("r.Route(")
                        if match = line.match(/r\.Route\(\s*"([^"]+)"/)
                          prefix_stack << match[1]
                        end
                        next
                      end

                      # 블록 종료 시 접두사 제거 (단순히 '}'만 있는 줄로 처리)
                      if line.strip == "}" && !prefix_stack.empty?
                        prefix_stack.pop
                        next
                      end

                      # 실제 endpoint 처리: r.Get, r.Post, r.Put, r.Delete
                      method = ""
                      if line.includes?("r.Get(")
                        method = "GET"
                      elsif line.includes?("r.Post(")
                        method = "POST"
                      elsif line.includes?("r.Put(")
                        method = "PUT"
                      elsif line.includes?("r.Delete(")
                        method = "DELETE"
                      end

                      if method.size > 0
                        route_path = extract_route_path(line)
                        if route_path.size > 0
                          full_route = (prefix_stack.join("") + route_path).to_s
                          result << Endpoint.new(full_route, method, details)
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

    # 기존 extract_route_path: r.Get("/path", ...) 등에서 경로 추출
    def extract_route_path(line : String) : String
      if match = line.match(/r\.\w+\(\s*"([^"]+)"/)
        return match[1]
      end
      ""
    end

    # 주어진 파일 내에 정의된 router 함수의 내용을 추출하여 엔드포인트 정보로 변환
    def analyze_router_function(file_path : String, func_name : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = File.read(file_path)
      # 간단한 정규표현식으로 함수 블록 시작 위치 찾기
      if start_index = content.index("func #{func_name}(")
        # 함수 블록의 중괄호 범위를 찾기 위해 플래그 사용
        block_started = false
        brace_count = 0
        content.lines.each do |line|
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
            # 함수 내부에서 endpoint 처리 (r.Get, r.Post, ...)
            details = Details.new(PathInfo.new(file_path))
            method = ""
            if line.includes?("r.Get(")
              method = "GET"
            elsif line.includes?("r.Post(")
              method = "POST"
            elsif line.includes?("r.Put(")
              method = "PUT"
            elsif line.includes?("r.Delete(")
              method = "DELETE"
            end

            if method.size > 0
              route_path = extract_route_path(line)
              if route_path.size > 0
                endpoints << Endpoint.new(route_path, method, details)
              end
            end

            break if brace_count <= 0
          end
        end
      end
      endpoints
    end
  end
end