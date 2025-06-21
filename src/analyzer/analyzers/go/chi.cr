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
                  File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                    prefix_stack = [] of String
                    file.each_line.with_index do |line, index|
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

                      # 헤더 호출 건너뛰기 (예: c.Header.Get("X-API-Key"))
                      if line.includes?(".Header.Get(")
                        # TODO: 생각보다 복잡해져서 나중에 구현하기
                        next
                      end

                      # 블록 종료 시 접두사 제거 (단순히 '}'만 있는 줄로 처리)
                      if line.strip == "}" && !prefix_stack.empty?
                        prefix_stack.pop
                        next
                      end

                      # 실제 endpoint 처리: .Get, .Post, .Put, .Delete (임의 객체)
                      method = ""
                      route_path = ""
                      if match = line.match(/[a-zA-Z]\w*\.(Get|Post|Put|Delete)\(\s*"([^"]+)"/)
                        method = match[1].upcase
                        route_path = match[2]
                      end

                      if method.size > 0 && route_path.size > 0
                        full_route = prefix_stack.join("") + route_path
                        result << Endpoint.new(full_route, method, details)
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
            if match = line.match(/[a-zA-Z]\w*\.(Get|Post|Put|Delete)\(\s*"([^"]+)"/)
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
