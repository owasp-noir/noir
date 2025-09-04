require "../../../models/analyzer"

module Analyzer::Elixir
  class Plug < Analyzer
    def analyze
      # Source Analysis
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
                  if File.exists?(path) && (File.extname(path) == ".ex" || File.extname(path) == ".exs")
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      content = file.gets_to_end
                      endpoints = analyze_content(content, path)
                      endpoints.each do |endpoint|
                        if endpoint.method != ""
                          @result << endpoint
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
        logger.debug e
      end

      @result
    end

    def analyze_content(content : String, file_path : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Split content into lines for line-by-line analysis
      content.lines.each_with_index do |line, index|
        line_endpoints = line_to_endpoint(line.strip)
        line_endpoints.each do |endpoint|
          if endpoint.method != ""
            details = Details.new(PathInfo.new(file_path, index + 1))
            endpoint.details = details
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    def line_to_endpoint(line : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Match Plug.Router style route definitions
      # get "/path", do: ...
      line.scan(/get\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "GET")
      end

      line.scan(/post\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "POST")
      end

      line.scan(/put\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "PUT")
      end

      line.scan(/patch\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "PATCH")
      end

      line.scan(/delete\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "DELETE")
      end

      line.scan(/head\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "HEAD")
      end

      line.scan(/options\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "OPTIONS")
      end

      # Match forward statements: forward "/api", SomeModule
      line.scan(/forward\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "FORWARD")
      end

      # Match match statements with method patterns
      # match "/path", via: [:get, :post]
      if match = line.match(/match\s+["\']([^"\']+)["\'][^:]*via:\s*\[([^\]]+)\]/)
        path = match[1]
        methods_str = match[2]
        methods_str.scan(/:(\w+)/) do |method_match|
          endpoints << Endpoint.new(path, method_match[1].upcase)
        end
      end

      # Match simple match statements (defaults to GET)
      line.scan(/match\s+["\']([^"\']+)["\']/) do |match|
        # Only add if we didn't already match a via: pattern above
        unless line.includes?("via:")
          endpoints << Endpoint.new("#{match[1]}", "GET")
        end
      end

      endpoints
    end
  end
end