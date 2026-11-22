# Strict companion to route_middleware: attribution may over-approximate;
# a guard proof must preserve the router value and framework install order.
module Noir
  module TreeSitterGoRouteExtractor
    record MiddlewareProof, arg : String, rule : String, receiver : String = "", row : Int32 = -1, certified : Bool = true, prefix : String? = nil

    # The strict walk can prove a local install even on a router passed in
    # from elsewhere. Only a chain rooted at a known constructor is complete.
    record MiddlewareScope, steps : Array(MiddlewareProof), framework : String, complete : Bool
    alias MiddlewareChains = Hash(Int32, MiddlewareScope)

    alias RouterHandoffs = Hash(Tuple(Int32, String), MiddlewareScope)

    private record GuardWalk, routes : Hash(Int32, Array(GuardRouter)), handoffs : RouterHandoffs?

    private class FiberStack
      getter steps = [] of MiddlewareProof
      property? complete = true
    end

    private class GuardRouter
      getter middleware = [] of MiddlewareProof
      getter live = [] of GuardRouter
      getter? group : Bool
      getter framework : String

      property? complete : Bool

      getter fiber : FiberStack?
      getter prefix : String

      def initialize(@group = false, @framework = "", @complete = true, @fiber : FiberStack? = nil, @prefix = "")
        @fiber ||= FiberStack.new if @framework == "fiber"
      end

      def escape!
        @complete = false
        middleware.clear
        live.clear
      end

      def proofs : Array(MiddlewareProof)
        live.flat_map(&.proofs) + middleware
      end
    end

    # Uses the caller's tree, once per file. Only verified framework types
    # and constructors seed values; unknown wrappers never inherit semantics.
    # ponytail: function-local identifiers only; registrars, fields, accessors,
    # multiply-bound names stay matched until prefix expansion
    # carries value identity (not just a composed string) across those edges.
    def guard_middleware(root : LibTreeSitter::TSNode, source : String,
                         imports : Hash(String, String), chains : MiddlewareChains? = nil, handoffs : RouterHandoffs? = nil) : Hash(Int32, Array(MiddlewareProof))
      result = Hash(Int32, Array(MiddlewareProof)).new
      aliases = Hash(String, String).new
      imports.each do |name, path|
        framework = case path
                    when "github.com/gin-gonic/gin"                                 then "gin"
                    when "github.com/go-chi/chi", "github.com/go-chi/chi/v5"        then "chi"
                    when "github.com/labstack/echo", "github.com/labstack/echo/v4"  then "echo"
                    when "github.com/cloudwego/hertz/pkg/app/server"                then "hertz"
                    when "github.com/kataras/iris/v12", "github.com/kataras/iris"   then "iris"
                    when "github.com/julienschmidt/httprouter"                      then "httprouter"
                    when "github.com/gorilla/mux"                                   then "mux"
                    when "github.com/gofiber/fiber/v2"                              then "fiber"
                    when "gitea.dev/modules/web", "code.gitea.io/gitea/modules/web" then "gitea"
                    end
        aliases[name] = framework if framework
      end
      return result if aliases.empty?
      registrations = Hash(Int32, Int32).new(0)
      Noir::TreeSitter.walk(root) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        function = Noir::TreeSitter.field(call, "function") || next
        next unless Noir::TreeSitter.node_type(function) == "selector_expression"
        field = Noir::TreeSitter.field(function, "field") || next
        method = Noir::TreeSitter.node_text(field, source)
        args = Noir::TreeSitter.field(call, "arguments") || next
        count = Noir::TreeSitter.named_arg_count(args)
        route = (HTTP_VERB_METHODS.includes?(method) || {"Handle", "HandleFunc", "Mount"}.includes?(method)) && count > 1
        route ||= {"Method", "MethodFunc", "Methods", "Add", "Match"}.includes?(method) && count > 2
        registrations[Noir::TreeSitter.node_start_row(call)] += 1 if route
      end
      pending = GuardWalk.new(Hash(Int32, Array(GuardRouter)).new, handoffs)
      Noir::TreeSitter.walk(root) do |function|
        next unless {"function_declaration", "method_declaration"}.includes?(Noir::TreeSitter.node_type(function))
        guard_function(function, source, aliases, Hash(String, GuardRouter).new, pending)
      end
      pending.routes.each do |row, routers|
        # Multiple registrations on a line cannot be distinguished by PathInfo.
        next unless routers.size == 1 && registrations[row] == 1
        router = routers.first
        steps = router.proofs
        result[row] = steps.select(&.certified)
        chains[row] = MiddlewareScope.new(steps, router.framework, router.complete? && router.live.all?(&.complete?)) if chains
      end
      result
    end

    private def guard_function(function : LibTreeSitter::TSNode, source : String, aliases : Hash(String, String),
                               inherited : Hash(String, GuardRouter), pending : GuardWalk,
                               framework : String = "")
      body = Noir::TreeSitter.field(function, "body") || return
      bindings = Hash(String, Int32).new(0)
      guard_bindings(function, source, bindings, true)
      env = Hash(String, GuardRouter).new
      aliases = aliases.reject { |name, _| bindings.has_key?(name) }
      params = Noir::TreeSitter.field(function, "parameters")
      params.try do |list|
        Noir::TreeSitter.each_named_child(list) do |decl|
          type = Noir::TreeSitter.field(decl, "type") || next
          qualifier, _, name = Noir::TreeSitter.node_text(type, source).lchop('*').rpartition('.')
          kind = aliases[qualifier]? || next
          group = {"gin" => %w[RouterGroup], "echo" => %w[Group]}[kind]?.try(&.includes?(name)) || false
          root = {"gin" => %w[Engine IRouter IRoutes], "chi" => %w[Router Mux], "echo" => %w[Echo], "mux" => %w[Router], "fiber" => %w[App Router], "gitea" => %w[Router], "hertz" => %w[Hertz], "iris" => %w[Application Party], "httprouter" => %w[Router]}[kind].includes?(name)
          next unless group || root
          framework = kind
          Noir::TreeSitter.each_named_child(decl) do |id|
            next unless Noir::TreeSitter.node_type(id) == "identifier"
            key = Noir::TreeSitter.node_text(id, source)
            env[key] = inherited[key]? || GuardRouter.new(group, kind, complete: false)
          end
        end
      end
      bindings.each { |name, count| env.delete(name) if count > 1 }
      guard_walk(body, source, aliases, env, bindings, pending, framework, guard_first_exit(body))
    end

    # A whole-function veto is deliberately stricter than a lexical lookup.
    # Skip nested closures: chi callback parameters are separate values.
    private def guard_bindings(node : LibTreeSitter::TSNode, source : String, counts : Hash(String, Int32), head = false)
      type = Noir::TreeSitter.node_type(node)
      if type == "func_literal" && !head
        Noir::TreeSitter.field(node, "body").try { |body| guard_bindings(body, source, counts) }
        return
      end
      case type
      when "parameter_declaration", "var_spec"
        count_bound_names(node, source, counts)
        if type == "var_spec" && (right = Noir::TreeSitter.field(node, "value").try { |r| Noir::TreeSitter.first_named_child(r) })
          if Noir::TreeSitter.node_type(right) == "identifier"
            counts[Noir::TreeSitter.node_text(right, source)] += 2
          elsif (use = middleware_call(right, source, "Use")) && (receiver = use[0])
            counts[receiver] += 2
          end
        end
      when "unary_expression"
        if Noir::TreeSitter.field(node, "operator").try { |op| Noir::TreeSitter.node_text(op, source) } == "&"
          operand = Noir::TreeSitter.field(node, "operand")
          if operand
            Noir::TreeSitter.walk(operand) do |id|
              counts[Noir::TreeSitter.node_text(id, source)] += 2 if Noir::TreeSitter.node_type(id) == "identifier"
            end
          end
        end
      when "short_var_declaration", "assignment_statement", "range_clause"
        right = Noir::TreeSitter.field(node, "right").try { |r| Noir::TreeSitter.first_named_child(r) }
        if right
          if Noir::TreeSitter.node_type(right) == "identifier"
            counts[Noir::TreeSitter.node_text(right, source)] += 2
          elsif (use = middleware_call(right, source, "Use")) && (receiver = use[0])
            counts[receiver] += 2
          end
        end
        left = Noir::TreeSitter.field(node, "left")
        count_bound_names(left, source, counts)
        if left
          Noir::TreeSitter.each_named_child(left) do |target|
            next if Noir::TreeSitter.node_type(target) == "identifier"
            Noir::TreeSitter.walk(target) do |id|
              counts[Noir::TreeSitter.node_text(id, source)] += 2 if Noir::TreeSitter.node_type(id) == "identifier"
            end
          end
        end
      end
      Noir::TreeSitter.each_named_child(node) { |child| guard_bindings(child, source, counts) }
    end

    # Even a conditional early return can hand back a router before a
    # later Echo/mux Use executes. Do not certify anything beyond it.
    private def guard_first_exit(node : LibTreeSitter::TSNode) : UInt32
      type = Noir::TreeSitter.node_type(node)
      return UInt32::MAX if type == "func_literal"
      return 0_u32 if type == "goto_statement"
      return LibTreeSitter.ts_node_start_byte(node) if type == "return_statement"
      first = UInt32::MAX
      Noir::TreeSitter.each_named_child(node) { |child| first = Math.min(first, guard_first_exit(child)) }
      first
    end

    private def guard_walk(node : LibTreeSitter::TSNode, source : String, aliases : Hash(String, String),
                           env : Hash(String, GuardRouter), bindings : Hash(String, Int32),
                           pending : GuardWalk, framework : String, first_exit : UInt32)
      if LibTreeSitter.ts_node_start_byte(node) > first_exit
        mark_incomplete(node, source, env)
        return
      end
      type = Noir::TreeSitter.node_type(node)
      env = env.dup if type == "block"
      # No install in a conditional, loop, deferred/go call or arbitrary
      # closure proves coverage. Dropping their routes too is conservative.
      if {"if_statement", "expression_switch_statement", "type_switch_statement", "select_statement",
          "for_statement", "func_literal", "go_statement", "defer_statement"}.includes?(type)
        mark_incomplete(node, source, env)
        return
      end
      if group_assignment_node?(node)
        left = Noir::TreeSitter.field(node, type == "var_spec" ? "name" : "left").try { |n| identifier_or_first_child(n) }
        right = Noir::TreeSitter.field(node, type == "var_spec" ? "value" : "right").try { |n| Noir::TreeSitter.first_named_child(n) }
        return unless left && right && Noir::TreeSitter.node_type(left) == "identifier"
        name = Noir::TreeSitter.node_text(left, source)
        value = guard_operand(right, source, aliases, env, framework)
        unless bindings[name] == 1
          guard_escape(right, source, env, value_escape: true) unless value
          return
        end
        if value
          env[name] = value[0]
          framework = value[1]
        else
          guard_escape(right, source, env, value_escape: true)
        end
        return
      end
      if type == "call_expression"
        function = Noir::TreeSitter.field(node, "function")
        unless function && Noir::TreeSitter.node_type(function) == "selector_expression"
          record_router_handoff(node, source, env, pending.handoffs)
          guard_escape(node, source, env)
          return
        end
        field = Noir::TreeSitter.field(function, "field") || return
        operand = Noir::TreeSitter.field(function, "operand") || return
        method = Noir::TreeSitter.node_text(field, source)
        if mux_route_chain_call?(node, source) && {"Methods", "Queries", "Name", "Host", "Schemes", "Headers", "HeadersRegexp"}.includes?(method) && Noir::TreeSitter.node_type(operand) == "call_expression"
          guard_walk(operand, source, aliases, env, bindings, pending, framework, first_exit)
          return
        end
        value = guard_operand(operand, source, aliases, env, framework)
        unless value
          record_router_handoff(node, source, env, pending.handoffs)
          guard_escape(node, source, env)
          return
        end
        router, kind = value
        # These wrapper methods append middleware without replacing the
        # router or clearing its synchronous Group stack (router.go).
        return if kind == "gitea" && {"BeforeRouting", "AfterRouting", "Use"}.includes?(method)
        if (method == "Use" || (method == "Pre" && kind == "echo")) && kind != "gitea"
          if stack = router.fiber
            args = guard_args(node, source)
            certified = !router.group? && args.size == 1
            prefix = router.prefix
            if first = Noir::TreeSitter.field(node, "arguments").try { |list| Noir::TreeSitter.first_named_child(list) }
              if Noir::TreeSitter.node_type(first).in?("interpreted_string_literal", "raw_string_literal")
                prefix = group_join(prefix, decode_string_literal(first, source))
                args.shift?
              end
            end
            args.each { |arg| stack.steps << MiddlewareProof.new(arg, "router Use", Noir::TreeSitter.node_text(operand, source), Noir::TreeSitter.node_start_row(node), certified, prefix) }
            return
          end
          args = guard_args(node, source)
          receiver = Noir::TreeSitter.node_text(operand, source)
          args.each { |arg| router.middleware << MiddlewareProof.new(arg, method == "Pre" ? "Pre" : (router.group? ? "group Use" : "router Use"), receiver, Noir::TreeSitter.node_start_row(node), method == "Use") }
          return
        end
        # Gitea's wrapper synchronously invokes a no-parameter callback
        # while curMiddlewares holds the inherited + trailing arguments,
        # then restores it. It is not chi.Group's parameter sub-router.
        if kind == "gitea" && method == "Group" && (closure = chi_closure_arg(node))
          args = guard_args(node, source)
          params = Noir::TreeSitter.field(closure, "parameters")
          return unless params && Noir::TreeSitter.first_named_child(params).nil? && args.size >= 2
          child = GuardRouter.new(true, kind, router.complete?)
          child.middleware.concat(router.proofs)
          args.skip(2).each { |arg| child.middleware << MiddlewareProof.new(arg, "Gitea Group") }
          receiver = Noir::TreeSitter.node_text(operand, source)
          return unless env.has_key?(receiver)
          inner = env.dup
          inner[receiver] = child
          body = Noir::TreeSitter.field(closure, "body") || return
          guard_walk(body, source, aliases, inner, bindings, pending, kind, guard_first_exit(body))
          return
        end
        if kind == "chi" && {"Group", "Route"}.includes?(method) && (closure = chi_closure_arg(node))
          return unless guard_args(node, source).size == (method == "Group" ? 1 : 2)
          child = GuardRouter.new(true, kind, router.complete?)
          child.middleware.concat(router.proofs)
          param = extract_closure_first_param_name(closure, source) || return
          guard_function(closure, source, aliases, {param => child}, pending, kind)
          return
        end
        route = HTTP_VERB_METHODS.includes?(method) || (kind == "chi" && method == "Mount") || {"Handle", "HandleFunc", "Method", "MethodFunc", "Methods", "Add", "Match"}.includes?(method)
        unless route
          record_router_handoff(node, source, env, pending.handoffs)
          guard_escape(node, source, env)
          name = Noir::TreeSitter.node_text(operand, source)
          env.delete(name).try(&.escape!)
          return
        end
        leaf = GuardRouter.new(framework: kind, complete: router.complete?)
        # Gin/Echo group chains snapshot; Echo instances and mux remain live.
        leaf.middleware.concat(router.middleware)
        leaf.live.concat(router.live)
        if kind == "mux" || (kind == "echo" && !router.group?)
          leaf.middleware.clear
          leaf.live.clear
          leaf.live << router
        end
        if stack = router.fiber
          leaf.middleware.concat(stack.steps)
          leaf.complete = false unless stack.complete?
        end
        args = guard_args(node, source)
        path_args = {"Method", "MethodFunc", "Methods", "Add", "Match"}.includes?(method) ? 2 : 1
        handlers = args.skip(path_args)
        middleware = kind == "echo" ? handlers.skip(1) : handlers[0...-1]
        middleware.each { |arg| leaf.middleware << MiddlewareProof.new(arg, "route argument") }
        (pending.routes[Noir::TreeSitter.node_start_row(node)] ||= [] of GuardRouter) << leaf
        return
      end
      Noir::TreeSitter.each_named_child(node) { |child| guard_walk(child, source, aliases, env, bindings, pending, framework, first_exit) }
    end

    private def mark_incomplete(node, source, env)
      Noir::TreeSitter.walk(node) do |id|
        if Noir::TreeSitter.node_type(id) == "identifier"
          if router = env[Noir::TreeSitter.node_text(id, source)]?
            router.complete = false
            router.fiber.try(&.complete=(false))
          end
        end
      end
    end

    # Snapshot the known part of a router handed to an external registrar.
    # The engine chooses the builder and prefix; the guard walk owns the
    # value at the call. Later installs on a live router remain unresolved.
    private def record_router_handoff(call, source, env, handoffs)
      return unless handoffs
      list = Noir::TreeSitter.field(call, "arguments") || return
      row = Noir::TreeSitter.node_start_row(call)
      Noir::TreeSitter.each_named_arg(list) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "identifier"
        name = Noir::TreeSitter.node_text(arg, source)
        router = env[name]? || next
        steps = router.proofs
        router.fiber.try { |stack| steps.concat(stack.steps) }
        handoffs[{row, name}] = MiddlewareScope.new(steps, router.framework, false)
      end
    end

    # ponytail: an unknown call handed a router can mutate it. Stop using
    # that value afterwards, including live Echo/mux proofs already recorded.
    private def guard_escape(call : LibTreeSitter::TSNode, source : String, env : Hash(String, GuardRouter), value_escape : Bool = false)
      args = value_escape ? call : (Noir::TreeSitter.field(call, "arguments") || call)
      shadowed = Set(String).new
      if Noir::TreeSitter.node_type(call) == "func_literal"
        Noir::TreeSitter.field(call, "parameters").try do |params|
          Noir::TreeSitter.each_named_child(params) do |decl|
            Noir::TreeSitter.each_named_child(decl) do |id|
              shadowed << Noir::TreeSitter.node_text(id, source) if Noir::TreeSitter.node_type(id) == "identifier"
            end
          end
        end
      end
      Noir::TreeSitter.walk(args) do |id|
        next unless Noir::TreeSitter.node_type(id) == "identifier"
        name = Noir::TreeSitter.node_text(id, source)
        next if shadowed.includes?(name)
        env.delete(name).try(&.escape!)
      end
    end

    private def guard_args(call : LibTreeSitter::TSNode, source : String) : Array(String)
      args = [] of String
      Noir::TreeSitter.field(call, "arguments").try do |list|
        # Do not flatten spreads: an unread middleware slice can contain
        # handlers that terminate before the candidate guard is reached.
        Noir::TreeSitter.each_named_arg(list) { |arg| args << Noir::TreeSitter.node_text(arg, source) }
      end
      args
    end

    private def guard_operand(node : LibTreeSitter::TSNode, source : String, aliases : Hash(String, String),
                              env : Hash(String, GuardRouter), framework : String, depth : Int32 = 0) : Tuple(GuardRouter, String)?
      return if depth >= Noir::TreeSitter::MAX_AST_DEPTH
      if Noir::TreeSitter.node_type(node) == "identifier"
        name = Noir::TreeSitter.node_text(node, source)
        return {env[name], env[name].framework} if env.has_key?(name)
        return
      end
      return unless Noir::TreeSitter.node_type(node) == "call_expression"
      function = Noir::TreeSitter.field(node, "function") || return
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      field = Noir::TreeSitter.field(function, "field") || return
      operand = Noir::TreeSitter.field(function, "operand") || return
      method = Noir::TreeSitter.node_text(field, source)
      if Noir::TreeSitter.node_type(operand) == "identifier" && (kind = aliases[Noir::TreeSitter.node_text(operand, source)]?)
        constructors = {"gin" => %w[New Default], "chi" => %w[NewRouter NewMux], "echo" => %w[New], "mux" => %w[NewRouter], "fiber" => %w[New], "gitea" => %w[NewRouter], "hertz" => %w[New Default], "iris" => %w[New Default], "httprouter" => %w[New]}
        return {GuardRouter.new(false, kind), kind} if constructors[kind].includes?(method)
      end
      parent, kind = guard_operand(operand, source, aliases, env, framework, depth + 1) || return
      if method == "Use" && kind.in?("gin", "hertz", "iris")
        guard_args(node, source).each { |arg| parent.middleware << MiddlewareProof.new(arg, parent.group? ? "group Use" : "router Use") }
        return {parent, kind}
      end
      if kind == "mux" && method == "Subrouter"
        child = GuardRouter.new(true, kind, parent.complete?)
        child.live << parent
        return {child, kind}
      end
      if kind == "mux" && {"PathPrefix", "Path", "Host", "Schemes", "Methods", "Headers", "Queries", "NewRoute"}.includes?(method)
        return {parent, kind}
      end
      if (kind.in?("gin", "echo", "fiber", "hertz") && method == "Group") || (kind == "iris" && method == "Party") || (kind == "chi" && method == "With")
        # Use the same group-chain recognizer as route prefix extraction.
        if method == "Group"
          return unless group_binding(node, source) || group_chain_operand_info(node, source, Hash(String, String).new, "Group", ([] of String), Hash(String, String).new, Set(String).new)
        end
        if stack = parent.fiber
          args = Noir::TreeSitter.field(node, "arguments") || return
          path = Noir::TreeSitter.first_named_child(args).try { |arg| decode_string_literal(arg, source) if Noir::TreeSitter.node_type(arg).in?("interpreted_string_literal", "raw_string_literal") }
          unless path
            stack.complete = false
            return
          end
          prefix = group_join(parent.prefix, path)
          guard_args(node, source).skip(1).each do |arg|
            stack.steps << MiddlewareProof.new(arg, "group constructor", Noir::TreeSitter.node_text(operand, source), Noir::TreeSitter.node_start_row(node), false, prefix)
          end
          return {GuardRouter.new(true, kind, parent.complete?, stack, prefix), kind}
        end
        child = GuardRouter.new(true, kind, parent.complete?)
        if kind == "echo" && !parent.group?
          child.live << parent
        else
          child.middleware.concat(parent.middleware)
          child.live.concat(parent.live)
        end
        args = guard_args(node, source)
        args = args.skip(1) unless method == "With"
        args.each { |arg| child.middleware << MiddlewareProof.new(arg, method == "With" ? "chi With" : "group constructor", Noir::TreeSitter.node_text(operand, source), Noir::TreeSitter.node_start_row(node)) }
        return {child, kind}
      end
      nil
    end
  end
end
