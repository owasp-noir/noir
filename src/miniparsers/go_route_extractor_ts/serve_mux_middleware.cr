module Noir::TreeSitterGoRouteExtractor
  # Each use of a ServeMux as a value either exposes it, wraps it, or
  # hands it to another mux/local. A public second mount is a separate
  # chain, even when the analyzer reports just one endpoint for the route.
  class ServeMuxMiddleware
    private record Use, next_name : String?, steps : Array(RouteMiddleware)
    private alias Uses = Hash(String, Array(Use))

    @functions = [] of Tuple(Range(Int32, Int32), Uses)

    def initialize(source : String, file : String)
      Noir::TreeSitter.parse_go(source) do |root|
        Noir::TreeSitter.each_named_child(root) do |decl|
          next unless Noir::TreeSitter.node_type(decl).in?("function_declaration", "method_declaration")
          body = Noir::TreeSitter.field(decl, "body") || next
          next unless Noir::TreeSitter.node_text(body, source).includes?("Handle")
          uses = Uses.new
          collect(body, source, file, uses, 0)
          @functions << {Noir::TreeSitter.node_start_row(body)..Noir::TreeSitter.node_end_row(body), uses}
        end
      end
    end

    def chains(row : Int32, receiver : String) : Array(Array(RouteMiddleware))
      function = @functions.find { |range, _| range.includes?(row) }
      function ? follow(function[1], receiver, Set(String).new) : [] of Array(RouteMiddleware)
    end

    private def collect(node, source, file, uses, depth)
      type = Noir::TreeSitter.node_type(node)
      if type == "identifier"
        if use = value_use(node, source, file, depth > 1)
          (uses[Noir::TreeSitter.node_text(node, source)] ||= [] of Use) << use
        end
      else
        depth += 1 if type == "block"
        Noir::TreeSitter.each_named_child(node) { |child| collect(child, source, file, uses, depth) }
      end
    end

    private def value_use(node, source, file, conditional) : Use?
      steps = [] of RouteMiddleware
      parent = Noir::TreeSitter.parent(node) || return
      return unless Noir::TreeSitter.node_type(parent).in?("argument_list", "return_statement", "expression_list", "literal_element")
      while Noir::TreeSitter.node_type(parent) == "argument_list"
        call = Noir::TreeSitter.parent(parent) || break
        function = Noir::TreeSitter.field(call, "function") || break
        while Noir::TreeSitter.node_type(function) == "call_expression"
          function = Noir::TreeSitter.field(function, "function") || return
        end
        if field = Noir::TreeSitter.field(function, "field")
          method = Noir::TreeSitter.node_text(field, source)
          if method.in?("Handle", "HandleFunc")
            owner = Noir::TreeSitter.field(function, "operand") || return
            return Use.new(Noir::TreeSitter.node_text(owner, source), steps.reverse!)
          end
          break if method.in?("ListenAndServe", "ListenAndServeTLS", "Serve")
        end
        steps << RouteMiddleware.new(Noir::TreeSitter.node_text(function, source), file,
          conditional ? :conditional_mount : :mount)
        parent = Noir::TreeSitter.parent(call) || break
      end
      if Noir::TreeSitter.node_type(parent) == "expression_list"
        assignment = Noir::TreeSitter.parent(parent) || return
        if Noir::TreeSitter.node_type(assignment).in?("short_var_declaration", "assignment_statement", "var_spec")
          right = Noir::TreeSitter.field(assignment, "right") || Noir::TreeSitter.field(assignment, "value") || return
          return unless LibTreeSitter.ts_node_start_byte(parent) == LibTreeSitter.ts_node_start_byte(right)
          left = Noir::TreeSitter.field(assignment, "left") || Noir::TreeSitter.field(assignment, "name") || return
          return Use.new(Noir::TreeSitter.node_text(left, source), steps.reverse!)
        end
      end
      Use.new(nil, steps.reverse!)
    end

    private def follow(uses, name, seen) : Array(Array(RouteMiddleware))
      return [[] of RouteMiddleware] if seen.includes?(name) || seen.size > 8
      references = uses[name]? || return [[] of RouteMiddleware]
      seen = seen.dup << name
      rebound, served = references.partition { |use| use.next_name == name }
      prefix = rebound.reverse.flat_map(&.steps)
      served.flat_map do |use|
        outer = (target = use.next_name) ? follow(uses, target, seen) : [[] of RouteMiddleware]
        outer.map { |chain| chain + use.steps + prefix }
      end.uniq!
    end
  end
end
