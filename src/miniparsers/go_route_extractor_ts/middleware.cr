# Part of Noir::TreeSitterGoRouteExtractor: the middleware a route runs behind.
module Noir
  module TreeSitterGoRouteExtractor
    # A fallback for locations without a decoded Route (table entries and
    # framework-specific registrars). Read the arguments from the Go tree,
    # including a With or Combo chain continued from a previous line.
    record Registration, method : String, receiver : String, args : Array(String), before : Array(String), bindings : Array(String) do
      def matches?(verb)
        method.upcase == verb || method.in?("ANY", "Any", "All", "ALL", "Match", "Add", "Handle", "HandleFunc", "Handler", "HandlerFunc", "BindHandler", "Route", "Method", "MethodFunc", "Methods")
      end

      def chain(file : String, handler_first : Bool, args = @args) : Array(RouteMiddleware)
        steps = before.map { |arg| RouteMiddleware.new(arg, file, :chain, receiver: receiver) }
        return steps if args.empty?
        primary = handler_first ? 0 : args.size - 1
        args.each_with_index do |arg, index|
          steps << RouteMiddleware.new(arg, file) unless index == primary
        end
        bindings.each { |arg| steps << RouteMiddleware.new(arg, file, :bind, receiver: receiver) }
        steps << RouteMiddleware.new(args[primary], file, :route, true, receiver)
      end
    end

    record ScopeCall, method : String, receiver : String, args : Array(String), row : Int32, last : Int32,
      statement : String, chained : Bool
    record MiddlewareClosure, first : Int32, last : Int32, receiver : String, args : Array(String)

    class MiddlewareIndex
      getter handoffs = RouterHandoffs.new
      getter scopes = MiddlewareChains.new
      getter installs = Hash(Int32, Array(ScopeCall)).new
      getter closures = [] of MiddlewareClosure
      getter sites = [] of MiddlewareSite
      getter registrations = Hash(Int32, Array(Registration)).new

      def registration(row, verb, receiver = nil, args = nil, first_on_line = false)
        matches = registrations[row]?.try(&.select(&.matches?(verb))) || return
        # Prefer the registering call inside a mux .Methods("GET") suffix.
        matches.reject! { |call| call.method == "Methods" && call.args.empty? }
        if matches.size > 1 && receiver && args
          matches.select! { |call| call.receiver == receiver && call.args == args }
        end
        matches.first? if matches.size == 1 || first_on_line
      end
    end

    def middleware_index(source : String) : MiddlewareIndex
      index = MiddlewareIndex.new
      Noir::TreeSitter.parse_go(source) do |root|
        collect_middleware_sites(root, source, Int32::MAX, index.sites, extended: true)
        guard_middleware(root, source, Noir::GoCalleeExtractor.extract_import_aliases(root, source), index.scopes, index.handoffs)
        Noir::TreeSitter.walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          function = Noir::TreeSitter.field(node, "function") || next
          field = Noir::TreeSitter.field(function, "field") || next
          method = Noir::TreeSitter.node_text(field, source)
          if method.in?("Group", "Route", "Party", "PartyFunc", "Use", "Pre", "Middleware", "Bind", "ALLMap", "Map")
            index_scope_call(node, function, method, source, index)
          end
          next unless HTTP_VERB_METHODS.includes?(method) || method.in?("Handle", "HandleFunc", "Method", "MethodFunc", "Methods", "Add", "Match", "BindHandler", "Handler", "HandlerFunc") || (method == "Route" && guard_args(node, source).size >= 3)
          operand = Noir::TreeSitter.field(function, "operand") || next
          args = guard_args(node, source)
          before = [] of String
          combo = false
          while Noir::TreeSitter.node_type(operand) == "call_expression"
            head = Noir::TreeSitter.field(operand, "function") || break
            name = Noir::TreeSitter.field(head, "field").try { |id| Noir::TreeSitter.node_text(id, source) }
            case name
            when "Combo", "Group", "Party"
              before = guard_args(operand, source).skip(1) + before
              combo ||= name == "Combo"
            when "With", "Use", "Pre"
              before = guard_args(operand, source) + before
            end
            operand = Noir::TreeSitter.field(head, "operand") || break
          end
          skip = if combo
                   0
                 elsif method.in?("Handler", "HandlerFunc", "Method", "MethodFunc", "Add", "Match", "Route") || (method == "Handle" && args.size > 2)
                   2
                 else
                   1
                 end
          row = Noir::TreeSitter.node_start_row(field)
          call = Registration.new(method, Noir::TreeSitter.node_text(operand, source), args.skip(skip), before, route_bindings(node, source))
          (index.registrations[row] ||= [] of Registration) << call
          start = Noir::TreeSitter.node_start_row(node)
          (index.registrations[start] ||= [] of Registration) << call unless start == row
        end
      end
      index
    end

    # PocketBase installs middleware on the returned route. A line break
    # between the registration and Bind does not change the call tree.
    private def route_bindings(node, source) : Array(String)
      bindings = [] of String
      while selector = Noir::TreeSitter.parent(node)
        break unless Noir::TreeSitter.node_type(selector) == "selector_expression"
        call = Noir::TreeSitter.parent(selector) || break
        break unless Noir::TreeSitter.node_type(call) == "call_expression"
        field = Noir::TreeSitter.field(selector, "field") || break
        bindings.concat(guard_args(call, source)) if Noir::TreeSitter.node_text(field, source) == "Bind"
        node = call
      end
      bindings
    end

    private def index_scope_call(node, function, method, source, index)
      operand = Noir::TreeSitter.field(function, "operand") || return
      receiver = Noir::TreeSitter.node_text(operand, source)
      args = guard_args(node, source)
      row = Noir::TreeSitter.node_start_row(node) + 1
      group = method.in?("Group", "Route", "Party", "PartyFunc")
      if group && (closure = chi_closure_arg(node))
        param = extract_closure_first_param_name(closure, source) || receiver
        trailing = args.skip_while { |arg| !arg.starts_with?("func") }.skip(1)
        parent_router = operand
        while with_call = middleware_call(parent_router, source, "With")
          trailing = with_call[1] + trailing
          parent_router = with_call[2] || break
        end
        parent_name = Noir::TreeSitter.node_text(parent_router, source)
        index.sites << MiddlewareSite.new(param, row - 1, Noir::TreeSitter.node_end_row(closure), trailing, parent_name, verb: "callback")
        index.closures << MiddlewareClosure.new(Noir::TreeSitter.node_start_row(closure) + 1,
          Noir::TreeSitter.node_end_row(closure) + 1, param, trailing)
      end
      # Keep the enclosing chain/assignment for the legacy prefix matcher
      # used for unresolved router handoffs. Don't cross an argument list.
      statement = node
      while (parent = Noir::TreeSitter.parent(statement)) && Noir::TreeSitter.node_type(parent).in?("selector_expression", "call_expression", "expression_list", "short_var_declaration", "assignment_statement")
        statement = parent
      end
      chained = LibTreeSitter.ts_node_end_byte(node) != LibTreeSitter.ts_node_end_byte(statement) && Noir::TreeSitter.node_type(operand) == "call_expression" && Noir::TreeSitter.node_type(statement) == "call_expression" &&
                Noir::TreeSitter.parent(statement).try { |container| Noir::TreeSitter.node_type(container) == "expression_statement" } == true
      text = Noir::TreeSitter.node_text(statement, source)
      site = ScopeCall.new(method, receiver, group ? args.skip(1) : args, row, Noir::TreeSitter.node_end_row(statement) + 1, text, chained)
      (index.installs[row] ||= [] of ScopeCall) << site
    end

    def scoped_steps(scope : MiddlewareScope, path : String, url : String?) : Array(RouteMiddleware)
      # Echo Pre runs before routing, including Use installed earlier.
      pre, rest = scope.steps.partition { |step| step.rule == "Pre" }
      (pre + rest).compact_map do |step|
        next if step.rule == "route argument"
        next if url && (prefix = step.prefix) && !url.starts_with?(prefix.rstrip('/'))
        origin = step.rule.in?("router Use", "group Use", "Pre") ? :router : :mount
        RouteMiddleware.new(step.arg, path, origin, false, step.receiver, step.prefix, verb: step.rule, line: step.row + 1, scope_proven: step.certified)
      end
    end

    def resolved_registration(index : MiddlewareIndex, call : Registration, row : Int32, path : String,
                              echo : Bool, args : Array(String), url : String, legacy = false) : Array(RouteMiddleware)
      scope = index.scopes[row]?
      direct = call.chain(path, scope ? scope.framework == "echo" : echo, args)
      inherited = scope && !legacy ? scoped_steps(scope, path, url) : [] of RouteMiddleware
      # When the strict walk cannot establish router identity, retain local
      # bindings as heuristic evidence and leave external scope resolution open.
      if legacy || scope.nil?
        scoped_sites(index.sites, call.receiver, row).each do |site|
          next if (prefix = site.prefix) && !url.starts_with?(prefix)
          next if legacy && (site.parent || row - site.row > 5)
          origin = legacy ? :fallback : (site.parent ? :mount : :router)
          site.args.each do |arg|
            next if site.prefix && arg == site.args.first?
            inherited << RouteMiddleware.new(arg, path, origin, false, site.receiver, site.prefix, verb: site.verb, line: site.row + 1)
          end
        end
      end
      # A live mux subrouter can inherit a parent Use after construction.
      # Its recorded parent scope also supplies adjacent evidence to a
      # legacy endpoint that carries only a source location.
      if legacy && scope && scope.framework == "mux"
        scoped_steps(scope, path, url).each do |step|
          line = step.line || next
          inherited << step.copy_with(origin: :fallback) if step.origin == :router && (row - 4..row).includes?(line)
        end
      end
      if scope && !legacy
        proven = scope.steps.select { |step| step.rule == "route argument" && step.certified }.map(&.arg)
        direct.map! { |step| step.copy_with(scope_proven: !step.handler_position && proven.includes?(step.source)) }
        direct.reject! { |step| step.origin == :chain && inherited.any? { |other| other.source == step.source } }
      end
      inherited + direct
    end

    MIDDLEWARE_GATE_RE = /\.(?:Use|Group)\s*\(/

    # A `recv.Use(mw...)` call, or a `recv := parent.Group("/p", mw...)`
    # binding (`parent` set): the handler texts it puts in front of
    # `recv`'s routes from `row` down to `scope_end`, the last row of the
    # block that holds it.
    record MiddlewareSite, receiver : String, row : Int32, scope_end : Int32, args : Array(String), parent : String? = nil, prefix : String? = nil, verb : String = "Group"

    # Middleware handler texts each route runs behind, keyed by
    # `{route.line, route.router_name}`: the `.Use` calls on its router
    # above it and, for a group, the group's own middleware plus what its
    # parent carried where the group was cut. Same file and block scope
    # only.
    # ponytail: a router handed to another function (`setup(r)`) is not
    # followed into it; add when a corpus shows `Use` across that call.
    def route_middleware(source : String, routes : Array(Route), index : MiddlewareIndex? = nil) : Hash(Tuple(Int32, String), Array(String))
      result = Hash(Tuple(Int32, String), Array(String)).new
      return result if routes.empty? || !source.matches?(MIDDLEWARE_GATE_RE)
      if index
        sites = index.sites.select(&.verb.in?("Use", "Group"))
      else
        sites = [] of MiddlewareSite
        Noir::TreeSitter.parse_go(source) { |root| collect_middleware_sites(root, source, Int32::MAX, sites) }
      end
      return result if sites.empty?
      routes.each do |route|
        args = scoped_sites(sites, route.router_name, route.line).flat_map(&.args)
        result[{route.line, route.router_name}] = args unless args.empty?
      end
      result
    end

    def scoped_sites(sites : Array(MiddlewareSite), name : String, row : Int32) : Array(MiddlewareSite)
      in_scope = sites.select { |site| site.receiver == name && site.row < row <= site.scope_end }
      group = in_scope.select(&.parent).max_by?(&.row)
      uses = in_scope.select { |site| site.parent.nil? && (group.nil? || site.row > group.row) }
      return uses unless group && (parent = group.parent)
      scoped_sites(sites, parent, group.row) + [group] + uses
    end

    private def collect_middleware_sites(node : LibTreeSitter::TSNode, source : String, scope_end : Int32, sites : Array(MiddlewareSite), extended = false)
      case Noir::TreeSitter.node_type(node)
      when "block"
        scope_end = Noir::TreeSitter.node_end_row(node)
      when "call_expression"
        function = Noir::TreeSitter.field(node, "function")
        method = function.try { |fn| Noir::TreeSitter.field(fn, "field") }.try { |field| Noir::TreeSitter.node_text(field, source) }
        if method && (method == "Use" || (extended && method.in?("Pre", "UseRouter", "UseGlobal", "UseOnce", "Middleware", "Bind"))) &&
           (use = middleware_call(node, source, method)) && (recv = use[0])
          args = use[1]
          prefix = args.first?.try { |arg| arg.strip('"') if arg.starts_with?('"') }
          sites << MiddlewareSite.new(recv, Noir::TreeSitter.node_start_row(node), scope_end, args, prefix: prefix, verb: method)
        end
      when "short_var_declaration", "assignment_statement"
        left = Noir::TreeSitter.field(node, "left").try { |l| identifier_or_first_child(l) }
        rhs = Noir::TreeSitter.field(node, "right").try { |r| Noir::TreeSitter.first_named_child(r) }
        if left && rhs && Noir::TreeSitter.node_type(left) == "identifier" &&
           (group = group_binding(rhs, source, extended))
          sites << MiddlewareSite.new(Noir::TreeSitter.node_text(left, source), Noir::TreeSitter.node_start_row(node),
            scope_end, group[1], group[0], verb: group[2])
        end
      end
      Noir::TreeSitter.each_named_child(node) { |child| collect_middleware_sites(child, source, scope_end, sites, extended) }
    end

    # `parent.Group("/p", mw...)`, optionally chained `.Use(mw...)`:
    # `{parent, middleware texts}`.
    private def group_binding(call : LibTreeSitter::TSNode, source : String, extended = false) : Tuple(String, Array(String), String)?
      args = [] of String
      loop do
        use = middleware_call(call, source, "Use")
        use ||= middleware_call(call, source, "Bind") if extended
        if use
          args = use[1] + args
          return unless (operand = use[2]) && Noir::TreeSitter.node_type(operand) == "call_expression"
          call = operand
        elsif (group = middleware_call(call, source, "Group")) && (parent = group[0])
          return {parent, group[1] + args, "Group"}
        elsif extended
          %w[Party Route Subrouter With].each do |method|
            site = middleware_call(call, source, method) || next
            parent = site[0] || return
            extra = method == "With" ? site[1] : site[1].skip(1)
            return {parent, extra + args, method}
          end
          return
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
