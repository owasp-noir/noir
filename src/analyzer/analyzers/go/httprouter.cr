require "../../../models/analyzer"
require "../../../minilexers/golang"

module Analyzer::Go
  class Httprouter < Analyzer
    PARAM_PATTERNS = [
      {"ByName(", /ByName\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "path"},
      {"Query().Get(", /Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "query"},
      {"PostFormValue(", /PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "form"},
      {"Header.Get(", /Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "header"},
      {"Cookie(", /Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "cookie"},
    ]

    def analyze
      # Source Analysis
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
                    lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
                    last_endpoint = Endpoint.new("", "")

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      # Detect route definitions: router.GET("/path", handler), router.POST("/path", handler), etc.
                      if match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD|Handle)\s*\(\s*"(\/[^"]*)"/)
                        method = match[1].upcase
                        route_path = match[2]

                        if method == "HANDLE"
                          # router.Handle("METHOD", "/path", handler) - extract method from first arg
                          if handle_match = line.match(/\.Handle\s*\(\s*"([^"]+)"\s*,\s*"(\/[^"]*)"/)
                            method = handle_match[1].upcase
                            route_path = handle_match[2]
                          else
                            next
                          end
                        end

                        last_endpoint = add_endpoint(route_path, method, details)
                      elsif match = line.match(/\.(GET|POST|PUT|DELETE|PATCH|OPTIONS|HEAD)\s*\(/)
                        # Multi-line: method on this line, path on next line
                        method = match[1].upcase
                        if index + 1 < lines.size
                          next_line = lines[index + 1]
                          if path_match = next_line.match(/"(\/[^"]*)"/)
                            last_endpoint = add_endpoint(path_match[1], method, details)
                          end
                        end
                      end

                      # FormValue must be checked separately to avoid matching PostFormValue
                      if line.includes?("FormValue(") && !line.includes?("PostFormValue(")
                        extract_param(line, /(?<!Post)FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "query", last_endpoint)
                      end

                      PARAM_PATTERNS.each do |includes_check, regex, param_type|
                        if line.includes?(includes_check)
                          extract_param(line, regex, param_type, last_endpoint)
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

      result
    end

    private def add_endpoint(route_path : String, method : String, details : Details) : Endpoint
      if route_path.size > 0
        new_endpoint = Endpoint.new(route_path, method, details)
        result << new_endpoint
        new_endpoint
      else
        Endpoint.new("", "")
      end
    end

    private def extract_param(line : String, regex : Regex, param_type : String, endpoint : Endpoint)
      if param_match = line.match(regex)
        param_name = param_match[1]
        if param_name.size > 0 && endpoint.url != ""
          endpoint.params << Param.new(param_name, "", param_type)
        end
      end
    end
  end
end
