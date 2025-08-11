require "../../../models/analyzer"

module Analyzer::Rust
  class Rwf < Analyzer
    def analyze
      # Source Analysis
      # Look for route! macro calls and Controller implementations
      route_pattern = /route!\("([^"]+)"\s*=>\s*(\w+)\)/
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
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      file.each_line.with_index do |line, index|
                        # Look for route! macro definitions
                        if line.includes? "route!("
                          match = line.match(route_pattern)
                          if match
                            begin
                              route_path = match[1]
                              controller_name = match[2]
                              details = Details.new(PathInfo.new(path, index + 1))
                              # For rwf, we'll default to GET method since controllers handle method routing internally
                              result << Endpoint.new(route_path, "GET", details)
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
  end
end
