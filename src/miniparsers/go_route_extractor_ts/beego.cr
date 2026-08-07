# Part of Noir::TreeSitterGoRouteExtractor: beego router calls and controller mapping.
module Noir
  module TreeSitterGoRouteExtractor
    # Extracts Beego controller-style routes:
    #
    #   web.Router("/health", ctrl, "get:Health")          -> GET /health
    #   web.Router("/x", c, "get,post:Handle")             -> GET /x, POST /x
    #   web.Router("/x", c, "get:Read;post:Write")         -> GET /x, POST /x
    #   web.Router("/any", c, "*:Any")                     -> ANY /any (fan-out)
    #   web.Router("/", &MainController{})                 -> verb routes
    #                                                         for each HTTP
    #                                                         method the
    #                                                         controller
    #                                                         implements
    #
    # `controller_methods` (see `extract_controller_methods`) supplies the
    # method set for the mapping-less form; when the controller type can't
    # be resolved (e.g. a cross-package `&controllers.User{}`), the route
    # falls back to a single GET so the endpoint is still surfaced rather
    # than dropped. The Route's `handler` carries the controller-method
    # name so the analyzer can attribute it as a callee.
    def extract_beego_routes(source : String,
                             controller_methods : Hash(String, Array(String)) = Hash(String, Array(String)).new) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_go(source) do |root|
        string_values = collect_string_values(root, source)
        var_types = collect_controller_var_types(root, source)
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          decode_beego_router_call(node, source, controller_methods, var_types, string_values).each do |route|
            routes << route
          end
        end
      end
      dedupe_routes(routes)
    end

    # Decode a single `web.Router(...)` / `beego.Router(...)` call into
    # zero or more routes (one per resolved HTTP method).
    private def decode_beego_router_call(call : LibTreeSitter::TSNode,
                                         source : String,
                                         controller_methods : Hash(String, Array(String)),
                                         var_types : Hash(String, String),
                                         string_values : Hash(String, String)) : Array(Route)
      empty = [] of Route
      function = Noir::TreeSitter.field(call, "function")
      return empty unless function
      return empty unless Noir::TreeSitter.node_type(function) == "selector_expression"
      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return empty unless operand && field
      return empty unless Noir::TreeSitter.node_type(operand) == "identifier"
      return empty unless BEEGO_ROUTER_OPERANDS.includes?(Noir::TreeSitter.node_text(operand, source))
      return empty unless Noir::TreeSitter.node_text(field, source) == "Router"

      args = Noir::TreeSitter.field(call, "arguments")
      return empty unless args

      path = nil
      controller_node : LibTreeSitter::TSNode? = nil
      mapping = nil
      idx = 0
      Noir::TreeSitter.each_named_child(args) do |arg|
        case idx
        when 0 then path = string_expr_text(arg, source, string_values)
        when 1 then controller_node = arg
        when 2 then mapping = string_expr_text(arg, source, string_values)
        end
        idx += 1
      end
      route_path = path
      return empty if route_path.nil? || route_path.empty?

      line = Noir::TreeSitter.node_start_row(call)
      ctrl_type = controller_node.try { |n| controller_type_name(n, source, var_types) }

      if mapping && !mapping.empty?
        parse_beego_mapping(mapping).map do |verb, fn|
          Route.new("web", verb, route_path, route_path, fn, line)
        end
      else
        methods = ctrl_type.try { |t| controller_methods[t]? }
        if methods && !methods.empty?
          # `compact_map` + `[m]?` is defensive: `controller_methods`
          # only carries HTTP-verb-named methods today, but a non-verb
          # name would otherwise raise on the direct lookup.
          methods.compact_map do |m|
            if verb = BEEGO_CONTROLLER_HTTP_METHODS[m]?
              Route.new("web", verb, route_path, route_path, m, line)
            end
          end
        else
          # Unresolved controller type: surface the endpoint under GET so
          # it isn't dropped entirely. Beego controllers almost always
          # implement `Get()`, so GET is the safest single-method guess.
          [Route.new("web", "GET", route_path, route_path, ctrl_type || "", line)]
        end
      end
    end

    # Parse a Beego method-mapping string into `{HTTP_VERB, func_name}`
    # pairs. Format: `"get:Method;post,put:Other"` — `;`-separated
    # segments, each `methods:funcname`, methods `,`-separated, `*`
    # meaning "any method".
    private def parse_beego_mapping(mapping : String) : Array(Tuple(String, String))
      result = [] of Tuple(String, String)
      mapping.split(';').each do |segment|
        segment = segment.strip
        next if segment.empty?
        colon = segment.index(':')
        next unless colon
        methods = segment[0...colon]
        fn = segment[(colon + 1)..].strip
        methods.split(',').each do |m|
          m = m.strip
          next if m.empty?
          result << ({m == "*" ? "ANY" : m.upcase, fn})
        end
      end
      result
    end

    # Scan the file for `name := &Ctrl{}` / `name := Ctrl{}` bindings so a
    # later `web.Router("/x", name)` can resolve `name`'s controller type.
    private def collect_controller_var_types(root : LibTreeSitter::TSNode,
                                             source : String) : Hash(String, String)
      var_types = Hash(String, String).new
      walk(root) do |node|
        next unless group_assignment_node?(node)
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        if Noir::TreeSitter.node_type(node) == "var_spec"
          left = Noir::TreeSitter.field(node, "name")
          right = Noir::TreeSitter.field(node, "value")
        end
        next unless left && right
        name_node = identifier_or_first_child(left)
        rhs = first_named_child(right)
        next unless name_node && rhs
        next unless Noir::TreeSitter.node_type(name_node) == "identifier"
        type_name = composite_literal_type_name(rhs, source)
        next unless type_name
        var_types[Noir::TreeSitter.node_text(name_node, source)] ||= type_name
      end
      var_types
    end

    # Resolve a controller argument node to its (unqualified) type name.
    # `identifier` → look up the var binding; anything wrapping a
    # `composite_literal` (`&Ctrl{}`, `Ctrl{}`) → the literal's type.
    private def controller_type_name(node : LibTreeSitter::TSNode,
                                     source : String,
                                     var_types : Hash(String, String)) : String?
      if Noir::TreeSitter.node_type(node) == "identifier"
        return var_types[Noir::TreeSitter.node_text(node, source)]?
      end
      composite_literal_type_name(node, source)
    end

    # Find a `composite_literal` at or under `node` and return its
    # (pointer-stripped) LOCAL type name. A package-qualified literal
    # (`&pkg.Ctrl{}`) returns nil: in Go a qualified type always lives in
    # another package, so its methods are never in this directory's
    # controller-method map. Returning nil routes such a route to the
    # unresolved-controller fallback instead of mis-matching a local type
    # that happens to share the final identifier (`Ctrl`).
    private def composite_literal_type_name(node : LibTreeSitter::TSNode,
                                            source : String) : String?
      comp = find_composite_literal(node)
      return unless comp
      type_node = Noir::TreeSitter.field(comp, "type") || first_named_child(comp)
      return unless type_node
      text = Noir::TreeSitter.node_text(type_node, source).lchop('*')
      return if text.includes?('.')
      text
    end

    private def find_composite_literal(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      return node if Noir::TreeSitter.node_type(node) == "composite_literal"
      result : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(node) do |child|
        if found = find_composite_literal(child)
          result = found
          break
        end
      end
      result
    end

    # Type name of a method receiver: `(c *MainController)` → `MainController`.
    private def receiver_type_name(receiver : LibTreeSitter::TSNode,
                                   source : String) : String?
      Noir::TreeSitter.each_named_child(receiver) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "parameter_declaration"
        type_node = Noir::TreeSitter.field(decl, "type")
        next unless type_node
        return final_type_identifier(type_node, source)
      end
      nil
    end

    # Strip a leading `*` (pointer) and any package qualifier, returning
    # the final identifier of a type expression: `*pkg.Foo` → `Foo`.
    private def final_type_identifier(type_node : LibTreeSitter::TSNode,
                                      source : String) : String
      Noir::TreeSitter.node_text(type_node, source).lchop('*').split('.').last
    end
  end
end
