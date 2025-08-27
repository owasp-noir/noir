require "../../../models/analyzer"

module Analyzer::Rust
  class Gotham < Analyzer
    def analyze
      # Source Analysis for Gotham web framework
      # Gotham uses builder pattern: Router::builder().get("/path").to(handler)
      pattern = /\.(get|post|put|delete|patch|head|options)\s*\(\s*"([^"]+)"\s*\)/
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
                        # Look for Gotham routing patterns like .get("/path")
                        if line.includes?(".") && (line.includes?("get") || line.includes?("post") || 
                                                   line.includes?("put") || line.includes?("delete") ||
                                                   line.includes?("patch") || line.includes?("head") || 
                                                   line.includes?("options"))
                          match = line.match(pattern)
                          if match
                            begin
                              method = match[1]
                              route_path = match[2]
                              
                              # Parse path parameters (Gotham uses :param syntax)
                              params = [] of Param
                              final_path = route_path.gsub(/:(\w+)/) do |param_match|
                                param_name = param_match[1..-1] # Remove the ':'
                                params << Param.new(param_name, "", "path")
                                ":#{param_name}"
                              end
                              
                              details = Details.new(PathInfo.new(path, index + 1))
                              endpoint = Endpoint.new(final_path, method.upcase, details)
                              params.each do |param|
                                endpoint.push_param(param)
                              end
                              result << endpoint
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