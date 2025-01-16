require "../../../models/analyzer"

module Analyzer::Rust
  class Rocket < Analyzer
    def analyze
      # Source Analysis
      pattern = /#\[(get|post|delete|put)\("([^"]+)"(?:, data = "<([^>]+)>")?\)\]/
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
        
                  if File.exists?(path) && File.extname(path) == ".rs"
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      file.each_line.with_index do |line, index|
                        if line.includes?("#[") && line.includes?(")]")
                          match = line.match(pattern)
                          if match
                            begin
                              callback_argument = match[1]
                              route_argument = match[2]
        
                              details = Details.new(PathInfo.new(path, index + 1))
                              result << Endpoint.new("#{route_argument}", callback_to_method(callback_argument), details)
                            rescue
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
        end
      rescue e
      end

      result
    end

    def callback_to_method(str)
      method = str.split("(").first
      if !["get", "post", "put", "delete"].includes?(method)
        method = "get"
      end

      method.upcase
    end
  end
end
