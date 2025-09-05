require "../../../models/analyzer"
require "../../../utils/wait_group"

module Analyzer::Java
  class Vertx < Analyzer
    # Regex patterns for Vert.x route detection
    REGEX_ROUTER_ROUTE    = /router\.(get|post|put|delete|patch|head|options|connect|trace)\s*\(\s*["\']([^"\']*)["\'].*?\)/i
    REGEX_ROUTE_METHOD    = /\.route\s*\(\s*["\']([^"\']*)["\'].*?\)\s*\.\s*(get|post|put|delete|patch|head|options|connect|trace)\s*\(/i
    REGEX_ROUTER_INSTANCE = /Router\s+(\w+)\s*=\s*Router\.router\(\s*[^)]*\s*\)/
    REGEX_MOUNTSUBPATH    = /router\.mountSubRouter\s*\(\s*["\']([^"\']*)["\'].*?\)/i

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

                  if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
                    details = Details.new(PathInfo.new(path))
                    content = File.read(path, encoding: "utf-8", invalid: :skip)

                    # Skip if no Vert.x related content
                    next unless content.includes?("Router") || content.includes?("vertx")

                    # Find direct router method calls like router.get("/path", handler)
                    content.scan(REGEX_ROUTER_ROUTE) do |match|
                      next if match.size < 3
                      method = match[1].upcase
                      endpoint = match[2]

                      next if !["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE"].includes?(method)
                      next if endpoint.empty?

                      @result << Endpoint.new(endpoint, method, details)
                    end

                    # Find route().method() pattern calls
                    content.scan(REGEX_ROUTE_METHOD) do |match|
                      next if match.size < 3
                      endpoint = match[1]
                      method = match[2].upcase

                      next if !["GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS", "CONNECT", "TRACE"].includes?(method)
                      next if endpoint.empty?

                      @result << Endpoint.new(endpoint, method, details)
                    end

                    # Find sub-router mount points for base paths
                    content.scan(REGEX_MOUNTSUBPATH) do |match|
                      next if match.size < 2
                      endpoint = match[1]
                      next if endpoint.empty?

                      # Sub-routers typically handle multiple methods, so we'll add a GET as default
                      @result << Endpoint.new(endpoint, "GET", details)
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

      @result
    end
  end
end
