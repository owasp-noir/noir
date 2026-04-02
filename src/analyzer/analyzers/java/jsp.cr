require "../../../utils/utils.cr"
require "../../../models/analyzer"

module Analyzer::Java
  class Jsp < Analyzer
    def analyze
      # Source Analysis
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

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

                  relative_path = get_relative_path(base_path, path)

                  if File.exists?(path) && File.extname(path) == ".jsp"
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      params_query = [] of Param

                      file.each_line do |line|
                        if line.includes? "request.getParameter"
                          match = line.strip.match(/request\.getParameter\("(.*?)"\)/)
                          if match
                            param_name = match[1]
                            params_query << Param.new(param_name, "", "query")
                          end
                        end

                        if line.includes? "request.getAttribute"
                          match = line.strip.match(/request\.getAttribute\("(.*?)"\)/)
                          if match
                            param_name = match[1]
                            params_query << Param.new(param_name, "", "query")
                          end
                        end

                        if line.includes? "request.getHeader"
                          match = line.strip.match(/request\.getHeader\("(.*?)"\)/)
                          if match
                            param_name = match[1]
                            params_query << Param.new(param_name, "", "header")
                          end
                        end

                        if line.includes? "request.getCookies"
                          match = line.strip.match(/request\.getCookies/)
                          if match
                            params_query << Param.new("", "", "cookie")
                          end
                        end

                        if line.includes? "${param."
                          match = line.strip.match(/\$\{param\.(.*?)\}/)
                          if match
                            param_name = match[1]
                            params_query << Param.new(param_name, "", "query")
                          end
                        end
                      rescue
                        next
                      end
                      details = Details.new(PathInfo.new(path))
                      result << Endpoint.new("/#{relative_path}", "GET", params_query, details)
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
      Fiber.yield

      result
    end

    def allow_patterns
      ["request.getParameter", "request.getAttribute", "request.getHeader", "request.getCookies"]
    end
  end
end
