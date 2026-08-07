# Part of Noir::TreeSitterKotlinRouteExtractor: Spring Cloud Gateway route-locator builder chains.
module Noir
  module TreeSitterKotlinRouteExtractor
    private struct GatewayRoute
      getter verb : String
      getter path : String

      def initialize(@verb, @path)
      end
    end

    private def collect_gateway_routes(source : String,
                                       string_constants : Hash(String, String),
                                       routes : Array(Route))
      visible_source = visible_kotlin_code(source)
      helpers = gateway_predicate_helpers(source, visible_source, string_constants)
      return if helpers.empty?

      visible_source.each_line.with_index do |line, idx|
        next if line.includes?("fun PredicateSpec.")

        helpers.each do |name, route|
          next unless line.includes?(".#{name}(")
          routes << Route.new(route.verb, route.path, "", "", idx)
        end
      end
    end

    private def gateway_predicate_helpers(source : String,
                                          visible_source : String,
                                          string_constants : Hash(String, String)) : Hash(String, GatewayRoute)
      helpers = Hash(String, GatewayRoute).new
      lines = source.lines
      visible_lines = visible_source.lines
      i = 0

      while i < lines.size
        line = visible_lines[i]
        match = line.match(/\bfun\s+PredicateSpec\.([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?::\s*[^=]+)?=/)
        unless match
          i += 1
          next
        end

        name = match[1]
        expr = lines[i][(match.end(0) || line.size)..]? || ""
        j = i
        broke_on_decl = false
        unless expr.includes?(".path(")
          j = i + 1
          while j < lines.size
            visible_next_line = visible_lines[j]
            if visible_next_line.match(/^\s*(?:[A-Za-z_][A-Za-z0-9_<>.]*\s+)*fun\b/) ||
               visible_next_line.match(/^\s*(?:class|object|interface|companion\s+object)\b/)
              broke_on_decl = true
              break
            end
            break if visible_next_line.strip == "}"
            expr += "\n#{lines[j]}"
            break if visible_next_line.includes?(".path(")
            j += 1
          end
        end

        if route = gateway_route_from_expression(expr, string_constants)
          helpers[name] = route
        end

        # If the scan stopped ON a new declaration line, re-examine it rather than
        # skipping it — otherwise a back-to-back PredicateSpec helper is missed.
        i = broke_on_decl ? j : j + 1
      end

      helpers
    end

    private def gateway_route_from_expression(expr : String, string_constants : Hash(String, String)) : GatewayRoute?
      verb_match = expr.match(/method\s*\(\s*(?:HttpMethod|RequestMethod)\.([A-Z]+)\s*\)/)
      return unless verb_match

      path_match = expr.match(/\.path\s*\(\s*([^)]+?)\s*\)/)
      return unless path_match

      path = resolve_gateway_path(path_match[1], string_constants)
      return if path.empty?

      GatewayRoute.new(verb_match[1], path)
    end

    private def resolve_gateway_path(raw : String, string_constants : Hash(String, String)) : String
      value = raw.strip
      if match = value.match(/^"([^"]*)"$/)
        return match[1]
      end

      if resolved = string_constants[value]?
        return resolved
      end

      if idx = value.rindex('.')
        short_name = value[(idx + 1)..]
        if resolved = string_constants[short_name]?
          return resolved
        end
      end

      ""
    end
  end
end
