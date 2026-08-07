# Part of Noir::TreeSitterKotlinRouteExtractor: WebFlux functional router DSL (coRouter/router blocks).
module Noir
  module TreeSitterKotlinRouteExtractor
    # Spring WebFlux Kotlin DSL:
    #
    #   coRouter {
    #     "/posts".nest {
    #       GET("/{id}", postHandler::get)
    #     }
    #   }
    #
    # This is source-only by design: no file I/O and no Ktor-style
    # lowercase verbs. Handler method references are threaded through
    # the Route so the analyzer can reuse the existing Kotlin callee
    # walker when the handler type is visible in the router function
    # signature.
    private def collect_webflux_functional_routes(source : String, routes : Array(Route))
      handler_types = functional_handler_types(source)
      visible_lines = visible_kotlin_code(source).lines
      lines = source.lines

      router_depth : Int32? = nil
      depth = 0
      nests = [] of FunctionalNest

      lines.each_with_index do |line, idx|
        visible = visible_lines[idx]? || line
        opens = visible.count("{")
        closes = visible.count("}")

        if router_depth.nil? && visible.match(/\b(?:coRouter|router)\s*\{/)
          router_depth = depth + opens - closes
          router_depth = depth + 1 if router_depth <= depth
        end

        if rd = router_depth
          if visible.match(/\.nest\s*\{/) && (match = line.match(/"([^"]*)"\s*\.\s*nest\s*\{/))
            nests << FunctionalNest.new(depth + 1, match[1])
          end

          if visible.match(/\b(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(/) &&
             (match = line.match(/\b(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\s*\(\s*"([^"]*)"/))
            verb = match[1]
            path = join_functional_paths(nests.map(&.path), match[2])
            class_name = ""
            method_name = ""
            handler_reference : String? = nil

            if handler_match = line.match(/([A-Za-z_][A-Za-z0-9_]*)\s*::\s*([A-Za-z_][A-Za-z0-9_]*)/)
              receiver = handler_match[1]
              method_name = handler_match[2]
              class_name = handler_types[receiver]? || ""
              handler_reference = "#{receiver}::#{method_name}"
            end

            inline_callees = handler_reference ? [] of NamedTuple(name: String, line: Int32) : inline_functional_route_callees(line, idx + 1)
            routes << Route.new(verb, path, class_name, method_name, idx, handler_reference, inline_callees)
          end

          depth += opens - closes
          nests.reject! { |nest| nest.depth > depth }
          router_depth = nil if depth < rd
        else
          depth += opens - closes
        end
      end
    end

    private def inline_functional_route_callees(line : String, line_number : Int32) : Array(NamedTuple(name: String, line: Int32))
      open_idx = line.index('{')
      close_idx = line.rindex('}')
      return [] of NamedTuple(name: String, line: Int32) unless open_idx && close_idx && close_idx > open_idx

      body = line[(open_idx + 1)...close_idx]
      callees = [] of NamedTuple(name: String, line: Int32)
      body.scan(/(?:(\b[A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?(\b[A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |match|
        receiver = match[1]?
        leaf = match[2]
        name = receiver ? "#{receiver}.#{leaf}" : leaf
        callees << {name: name, line: line_number}
      end
      callees
    end

    private def functional_handler_types(source : String) : Hash(String, String)
      types = Hash(String, String).new
      source.scan(/\bfun\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)/) do |match|
        collect_functional_parameter_types(match[1], types)
      end
      source.scan(/\bclass\s+[A-Za-z_][A-Za-z0-9_]*\s*\(([^)]*)\)/) do |match|
        collect_functional_parameter_types(match[1], types)
      end
      types
    end

    private def collect_functional_parameter_types(parameter_list : String, types : Hash(String, String))
      parameter_list.scan(/(?:\b(?:private|protected|public|internal)\s+)*(?:val|var)?\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_.]*)/) do |param|
        types[param[1]] ||= param[2].split('.').last
      end
    end

    private def join_functional_paths(prefixes : Array(String), path : String) : String
      prefix = prefixes.reduce("") { |memo, item| join_paths(memo, item) }
      join_paths(prefix, path)
    end
  end
end
