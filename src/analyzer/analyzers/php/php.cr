require "../../../utils/utils.cr"
require "../../../models/analyzer"

module Analyzer::Php
  class Php < Analyzer
    def analyze
      # Source Analysis
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
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)

                  relative_path = get_relative_path(base_path, path)

                  if File.exists?(path) && File.extname(path) == ".php"
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      params_query = [] of Param
                      params_body = [] of Param
                      methods = [] of String

                      file.each_line do |line|
                        if allow_patterns.any? { |pattern| line.includes? pattern }
                          match = line.strip.match(/\$_(.*?)\['(.*?)'\]/)

                          if match
                            method = match[1]
                            param_name = match[2]

                            if method == "GET"
                              params_query << Param.new(param_name, "", "query")
                            elsif method == "POST"
                              params_body << Param.new(param_name, "", "form")
                              methods << "POST"
                            elsif method == "REQUEST"
                              params_query << Param.new(param_name, "", "query")
                              params_body << Param.new(param_name, "", "form")
                              methods << "POST"
                            elsif method == "SERVER"
                              if param_name.includes? "HTTP_"
                                param_name = param_name.sub("HTTP_", "").gsub("_", "-")
                                params_query << Param.new(param_name, "", "header")
                                params_body << Param.new(param_name, "", "header")
                              end
                            end
                          end
                        end
                      rescue
                        next
                      end

                      details = Details.new(PathInfo.new(path))
                      methods.each do |method|
                        result << Endpoint.new("/#{relative_path}", method, params_body, details)
                      end
                      result << Endpoint.new("/#{relative_path}", "GET", params_query, details)
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
      Fiber.yield

      result
    end

    def allow_patterns
      ["$_GET", "$_POST", "$_REQUEST", "$_SERVER"]
    end
  end
end
