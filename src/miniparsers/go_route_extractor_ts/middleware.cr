# Part of Noir::TreeSitterGoRouteExtractor: the middleware a route runs behind.
module Noir
  module TreeSitterGoRouteExtractor
    MIDDLEWARE_GATE_RE = /\.(?:Use|Group)\s*\(/

    # A `recv.Use(mw...)` call, or a `recv := parent.Group("/p", mw...)`
    # binding (`parent` set): the handler texts it puts in front of
    # `recv`'s routes from `row` down to `scope_end`, the last row of the
    # block that holds it.
    private record MiddlewareSite, receiver : String, row : Int32, scope_end : Int32, args : Array(String), parent : String? = nil

    # Middleware handler texts each route runs behind, keyed by
    # `{route.line, route.router_name}`: the `.Use` calls on its router
    # above it and, for a group, the group's own middleware plus what its
    # parent carried where the group was cut. Same file and block scope
    # only.
    # ponytail: a router handed to another function (`setup(r)`) is not
    # followed into it; add when a corpus shows `Use` across that call.
    def route_middleware(source : String, routes : Array(Route)) : Hash(Tuple(Int32, String), Array(String))
      result = Hash(Tuple(Int32, String), Array(String)).new
      return result if routes.empty? || !source.matches?(MIDDLEWARE_GATE_RE)
      sites = [] of MiddlewareSite
      Noir::TreeSitter.parse_go(source) { |root| collect_middleware_sites(root, source, Int32::MAX, sites) }
      return result if sites.empty?
      routes.each do |route|
        args = middleware_for(sites, route.router_name, route.line)
        result[{route.line, route.router_name}] = args unless args.empty?
      end
      result
    end

    private def middleware_for(sites : Array(MiddlewareSite), name : String, row : Int32) : Array(String)
      in_scope = sites.select { |s| s.receiver == name && s.row < row && row <= s.scope_end }
      group = in_scope.select(&.parent).max_by?(&.row)
      uses = in_scope.select { |s| s.parent.nil? && (group.nil? || s.row > group.row) }.flat_map(&.args)
      return uses unless group && (parent = group.parent)
      # Rows strictly decrease, so `r = r.Group(...)` terminates.
      middleware_for(sites, parent, group.row) + group.args + uses
    end

    private def collect_middleware_sites(node : LibTreeSitter::TSNode, source : String, scope_end : Int32, sites : Array(MiddlewareSite))
      case Noir::TreeSitter.node_type(node)
      when "block"
        scope_end = Noir::TreeSitter.node_end_row(node)
      when "call_expression"
        if (use = middleware_call(node, source, "Use")) && (recv = use[0])
          sites << MiddlewareSite.new(recv, Noir::TreeSitter.node_start_row(node), scope_end, use[1])
        end
      when "short_var_declaration", "assignment_statement"
        left = Noir::TreeSitter.field(node, "left").try { |l| identifier_or_first_child(l) }
        rhs = Noir::TreeSitter.field(node, "right").try { |r| Noir::TreeSitter.first_named_child(r) }
        if left && rhs && Noir::TreeSitter.node_type(left) == "identifier" &&
           (group = group_binding(rhs, source))
          sites << MiddlewareSite.new(Noir::TreeSitter.node_text(left, source), Noir::TreeSitter.node_start_row(node),
            scope_end, group[1], group[0])
        end
      end
      Noir::TreeSitter.each_named_child(node) { |child| collect_middleware_sites(child, source, scope_end, sites) }
    end

    # `parent.Group("/p", mw...)`, optionally chained `.Use(mw...)`:
    # `{parent, middleware texts}`.
    private def group_binding(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String))?
      args = [] of String
      loop do
        if use = middleware_call(call, source, "Use")
          args = use[1] + args
          return unless (operand = use[2]) && Noir::TreeSitter.node_type(operand) == "call_expression"
          call = operand
        elsif (group = middleware_call(call, source, "Group")) && (parent = group[0])
          return {parent, group[1] + args}
        else
          return
        end
      end
    end

    # `operand.method(args...)`: `{operand name if an identifier, handler
    # texts of the args, operand}`. A `Group`'s first arg is its path.
    private def middleware_call(call : LibTreeSitter::TSNode, source : String, method : String) : Tuple(String?, Array(String), LibTreeSitter::TSNode?)?
      return unless Noir::TreeSitter.node_type(call) == "call_expression"
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "selector_expression"
      return unless Noir::TreeSitter.field(function, "field").try { |f| Noir::TreeSitter.node_text(f, source) } == method
      operand = Noir::TreeSitter.field(function, "operand")
      name = operand && Noir::TreeSitter.node_type(operand) == "identifier" ? Noir::TreeSitter.node_text(operand, source) : nil
      texts = [] of String
      Noir::TreeSitter.field(call, "arguments").try do |args|
        Noir::TreeSitter.each_named_arg(args) { |arg| collect_handler_arg_texts(arg, source, texts) }
        texts.shift? if method == "Group"
      end
      {name, texts, operand}
    end
  end
end
