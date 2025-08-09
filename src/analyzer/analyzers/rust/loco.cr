require "../../../models/analyzer"

module Analyzer::Rust
  class Loco < Analyzer
    def analyze
      # Source Analysis for Loco framework routes
      # Loco typically uses controller methods and route definitions
      # Common patterns include controller actions and route handlers
      
      # Pattern for controller methods and route handlers
      # This covers common Loco patterns like controller actions
      patterns = [
        # Controller action methods (common in Loco controllers)
        /pub\s+async\s+fn\s+(\w+)\s*\([^)]*Request[^)]*\)\s*->\s*Result<[^>]*Response/,
        # Route handler functions
        /async\s+fn\s+(\w+)\s*\([^)]*\)\s*->\s*(?:Result<|impl\s+).*Response/,
        # Loco controller methods with various patterns
        /fn\s+(\w+)\s*\([^)]*&self[^)]*Request[^)]*\)\s*->\s*Result/
      ]
      
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
                        patterns.each do |pattern|
                          match = line.match(pattern)
                          if match
                            begin
                              method_name = match[1]
                              # Generate endpoint path based on method name
                              # This is a heuristic since Loco routes might be defined separately
                              endpoint_path = "/#{method_name.gsub(/([A-Z])/, "_\\1").downcase.lstrip("_")}"
                              details = Details.new(PathInfo.new(path, index + 1))
                              # Default to GET method, could be enhanced with more pattern matching
                              result << Endpoint.new(endpoint_path, "GET", details)
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