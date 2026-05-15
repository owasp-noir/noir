require "../../../models/analyzer"
require "../../../miniparsers/java_callee_extractor"
require "wait_group"

module Analyzer::Java
  class Vertx < Analyzer
    # Regex patterns for Vert.x route detection
    REGEX_ROUTER_ROUTE         = /router\.(get|post|put|delete|patch|head|options|connect|trace)\s*\(\s*["\']([^"\']*)["\'].*?\)/i
    REGEX_ROUTE_METHOD         = /\.route\s*\(\s*["\']([^"\']*)["\'].*?\)\s*\.\s*(get|post|put|delete|patch|head|options|connect|trace)\s*\(/i
    REGEX_ROUTER_ROUTE_HANDLER = /router\.(get|post|put|delete|patch|head|options|connect|trace)\s*\(\s*["\']([^"\']*)["\']\s*\)\s*\.handler\s*\(\s*this::([\w$]+)\s*\)/i
    REGEX_ROUTE_METHOD_HANDLER = /\.route\s*\(\s*["\']([^"\']*)["\']\s*\)\s*\.\s*(get|post|put|delete|patch|head|options|connect|trace)\s*\(\s*this::([\w$]+)\s*\)/i
    REGEX_ROUTER_INSTANCE      = /Router\s+(\w+)\s*=\s*Router\.router\(\s*[^)]*\s*\)/
    REGEX_MOUNTSUBPATH         = /router\.mountSubRouter\s*\(\s*["\']([^"\']*)["\'].*?\)/i

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

                  if File.exists?(path) && (path.ends_with?(".java") || path.ends_with?(".kt"))
                    details = Details.new(PathInfo.new(path))
                    content = read_file_content(path)

                    # Skip if no Vert.x related content
                    next unless content.includes?("Router") || content.includes?("vertx")

                    callees_by_route = extract_method_reference_callees(content, path)

                    # Find direct router method calls like router.get("/path", handler)
                    content.scan(REGEX_ROUTER_ROUTE) do |match|
                      next if match.size < 3
                      method = match[1].upcase
                      endpoint = match[2]

                      next if !method.in?(%w[GET POST PUT DELETE PATCH HEAD OPTIONS CONNECT TRACE])
                      next if endpoint.empty?

                      found = Endpoint.new(endpoint, method, details)
                      attach_callees(found, callees_by_route, method, endpoint)
                      @result << found
                    end

                    # Find route().method() pattern calls
                    content.scan(REGEX_ROUTE_METHOD) do |match|
                      next if match.size < 3
                      endpoint = match[1]
                      method = match[2].upcase

                      next if !method.in?(%w[GET POST PUT DELETE PATCH HEAD OPTIONS CONNECT TRACE])
                      next if endpoint.empty?

                      found = Endpoint.new(endpoint, method, details)
                      attach_callees(found, callees_by_route, method, endpoint)
                      @result << found
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

      @result
    end

    private def extract_method_reference_callees(content : String, path : String) : Hash(String, Array(Callee))
      handlers_by_route = {} of String => String

      content.scan(REGEX_ROUTER_ROUTE_HANDLER) do |match|
        next if match.size < 4
        method = match[1].upcase
        endpoint = match[2]
        handler_name = match[3]
        next if endpoint.empty? || handler_name.empty?

        handlers_by_route[route_key(method, endpoint)] = handler_name
      end

      content.scan(REGEX_ROUTE_METHOD_HANDLER) do |match|
        next if match.size < 4
        endpoint = match[1]
        method = match[2].upcase
        handler_name = match[3]
        next if endpoint.empty? || handler_name.empty?

        handlers_by_route[route_key(method, endpoint)] = handler_name
      end

      return {} of String => Array(Callee) if handlers_by_route.empty?

      wanted_handlers = handlers_by_route.values.uniq!
      callees_by_handler = {} of String => Array(Callee)

      Noir::TreeSitter.parse_java(content) do |root|
        walk_method_declarations(root) do |method|
          name_node = Noir::TreeSitter.field(method, "name")
          next unless name_node

          method_name = Noir::TreeSitter.node_text(name_node, content)
          next unless wanted_handlers.includes?(method_name)
          next if callees_by_handler.has_key?(method_name)

          body = Noir::TreeSitter.field(method, "body")
          next unless body

          callees_by_handler[method_name] = Noir::JavaCalleeExtractor.callees_in_body(body, content, path).map do |(name, callee_path, callee_line)|
            Callee.new(name, path: callee_path, line: callee_line)
          end
        end
      end

      callees_by_route = {} of String => Array(Callee)
      handlers_by_route.each do |key, handler_name|
        if callees = callees_by_handler[handler_name]?
          callees_by_route[key] = callees
        end
      end
      callees_by_route
    end

    private def attach_callees(endpoint : Endpoint, callees_by_route : Hash(String, Array(Callee)), method : String, route : String)
      callees = callees_by_route[route_key(method, route)]?
      return unless callees

      callees.each do |callee|
        endpoint.push_callee(callee)
      end
    end

    private def route_key(method : String, route : String) : String
      "#{method.upcase}::#{route}"
    end

    private def walk_method_declarations(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      if Noir::TreeSitter.node_type(node) == "method_declaration"
        block.call(node)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_method_declarations(child, &block)
      end
    end
  end
end
