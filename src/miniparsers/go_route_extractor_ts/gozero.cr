# Part of Noir::TreeSitterGoRouteExtractor: go-zero route structs and group prefixes.
module Noir
  module TreeSitterGoRouteExtractor
    # go-zero registers routes as `rest.Route` struct literals rather than
    # verb calls, in two shapes:
    #
    #   server.AddRoutes(                       # generated routes.go
    #     []rest.Route{
    #       {Method: http.MethodPost, Path: "/user/login", Handler: h},
    #     },
    #     rest.WithPrefix("/usercenter/v1"),
    #   )
    #
    #   server.AddRoute(rest.Route{Method: http.MethodGet, Path: "/"})
    #   apiGroup := server.Group("/api/v1")     # hand-written grouping
    #   apiGroup.AddRoute(rest.Route{Path: "/products", ...})
    #
    # The verb/path live in the struct (not a `.Get(...)` call), and the
    # mount prefix comes from a trailing `rest.WithPrefix(...)` option
    # and/or a `server.Group("/p")` receiver — so the generic verb
    # extractor sees nothing. This decodes every route to its full mounted
    # path so it dedupes against the same route declared (prefix-applied)
    # in a `.api` file. `handler` carries the registered handler
    # expression for callee wiring.
    def extract_gozero_routes(source : String) : Array(Route)
      results = [] of Route
      Noir::TreeSitter.parse_go(source) do |root|
        group_prefixes = collect_gozero_group_prefixes(root, source)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          function = Noir::TreeSitter.field(node, "function")
          next if function.nil?
          next unless Noir::TreeSitter.node_type(function) == "selector_expression"
          fname_node = Noir::TreeSitter.field(function, "field")
          next if fname_node.nil?
          fname = Noir::TreeSitter.node_text(fname_node, source)
          next unless fname == "AddRoute" || fname == "AddRoutes"

          # The receiver may be the root server/engine (no prefix) or a
          # `:= server.Group("/p")` variable whose prefix we resolved.
          receiver = Noir::TreeSitter.field(function, "operand")
          base_prefix = ""
          if receiver && Noir::TreeSitter.node_type(receiver) == "identifier"
            base_prefix = group_prefixes[Noir::TreeSitter.node_text(receiver, source)]? || ""
          end

          args = Noir::TreeSitter.field(node, "arguments")
          next if args.nil?

          with_prefix = ""
          route_literal = nil
          Noir::TreeSitter.each_named_child(args) do |arg|
            case Noir::TreeSitter.node_type(arg)
            when "composite_literal"
              route_literal ||= arg
            when "call_expression"
              if p = gozero_with_prefix(arg, source)
                with_prefix = p
              end
            end
          end
          rl = route_literal
          next if rl.nil?

          prefix = "#{normalize_gozero_prefix(base_prefix)}#{normalize_gozero_prefix(with_prefix)}"

          # `[]rest.Route{...}` (slice) holds one struct per element;
          # `rest.Route{...}` (singular) is itself one route struct.
          type_node = Noir::TreeSitter.field(rl, "type")
          type_text = type_node ? Noir::TreeSitter.node_text(type_node, source) : ""
          body = Noir::TreeSitter.field(rl, "body")
          next if body.nil?

          if type_text.starts_with?("[]")
            Noir::TreeSitter.each_named_child(body) do |elem|
              inner = gozero_inner_value(elem)
              next if inner.nil?
              if route = gozero_decode_route_struct(inner, prefix, source, elem)
                results << route
              end
            end
          else
            if route = gozero_decode_route_struct(body, prefix, source, rl)
              results << route
            end
          end
        end
      end
      results
    end

    private def normalize_gozero_prefix(prefix : String) : String
      return "" if prefix.empty?
      prefix.starts_with?("/") ? prefix : "/#{prefix}"
    end

    # Decode a single `rest.Route{Method:..., Path:..., Handler:...}`
    # struct (given its `literal_value` body) into a Route, applying the
    # resolved mount prefix.
    private def gozero_decode_route_struct(inner : LibTreeSitter::TSNode, prefix : String,
                                           source : String, line_node : LibTreeSitter::TSNode) : Route?
      method = ""
      rpath = ""
      handler = ""
      Noir::TreeSitter.each_named_child(inner) do |kv|
        next unless Noir::TreeSitter.node_type(kv) == "keyed_element"
        key_node, val_node = gozero_keyed_pair(kv)
        next if key_node.nil? || val_node.nil?
        case Noir::TreeSitter.node_text(key_node, source)
        when "Method"  then method = decode_method_token(val_node, source)
        when "Path"    then rpath = gozero_string_value(val_node, source)
        when "Handler" then handler = Noir::TreeSitter.node_text(val_node, source)
        end
      end
      return if method.empty? || rpath.empty?
      return unless rpath.starts_with?("/")
      full = "#{prefix}#{rpath}"
      Route.new("server", method, full, rpath, handler, Noir::TreeSitter.node_start_row(line_node))
    end

    # Collect `groupVar := <recv>.Group("/p")` bindings, resolving nested
    # groups to their full prefix. The root receiver (`server`/`engine`)
    # contributes no prefix; a group-on-group accumulates. Iterated to a
    # fixpoint so `g2 := g1.Group("/x")` resolves regardless of source
    # order.
    private def collect_gozero_group_prefixes(root : LibTreeSitter::TSNode, source : String) : Hash(String, String)
      prefixes = Hash(String, String).new
      10.times do
        changed = false
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "short_var_declaration"
          left = Noir::TreeSitter.field(node, "left")
          right = Noir::TreeSitter.field(node, "right")
          next if left.nil? || right.nil?
          var = first_named_child(left)
          rhs = first_named_child(right)
          next if var.nil? || rhs.nil?
          next unless Noir::TreeSitter.node_type(var) == "identifier"
          next unless Noir::TreeSitter.node_type(rhs) == "call_expression"
          func = Noir::TreeSitter.field(rhs, "function")
          next if func.nil? || Noir::TreeSitter.node_type(func) != "selector_expression"
          fld = Noir::TreeSitter.field(func, "field")
          next if fld.nil? || Noir::TreeSitter.node_text(fld, source) != "Group"
          recv = Noir::TreeSitter.field(func, "operand")
          next if recv.nil? || Noir::TreeSitter.node_type(recv) != "identifier"
          pstr = nil
          if rargs = Noir::TreeSitter.field(rhs, "arguments")
            Noir::TreeSitter.each_named_child(rargs) do |arg|
              s = gozero_string_value(arg, source)
              if pstr.nil? && !s.empty?
                pstr = s
              end
            end
          end
          next if pstr.nil?
          recv_name = Noir::TreeSitter.node_text(recv, source)
          base = (recv_name == "server" || recv_name == "engine") ? "" : (prefixes[recv_name]? || "")
          val = "#{base}#{normalize_gozero_prefix(pstr)}"
          vname = Noir::TreeSitter.node_text(var, source)
          if prefixes[vname]? != val
            prefixes[vname] = val
            changed = true
          end
        end
        break unless changed
      end
      prefixes
    end

    # Resolve a slice element to the `literal_value` holding its keyed
    # fields — transparent to a `literal_element` wrapper, an explicit
    # `rest.Route{...}` composite_literal, or a bare `{...}` literal_value.
    private def gozero_inner_value(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      n = node
      if Noir::TreeSitter.node_type(n) == "literal_element"
        fc = first_named_child(n)
        return if fc.nil?
        n = fc
      end
      case Noir::TreeSitter.node_type(n)
      when "literal_value"
        n
      when "composite_literal"
        Noir::TreeSitter.field(n, "body")
      end
    end

    # Unwrap a `literal_element` container (tree-sitter-go wraps both
    # sides of a keyed_element) to reach the underlying key/value node.
    private def gozero_unwrap(node : LibTreeSitter::TSNode?) : LibTreeSitter::TSNode?
      return if node.nil?
      if Noir::TreeSitter.node_type(node) == "literal_element"
        return first_named_child(node)
      end
      node
    end

    private def gozero_keyed_pair(kv : LibTreeSitter::TSNode) : Tuple(LibTreeSitter::TSNode?, LibTreeSitter::TSNode?)
      key = Noir::TreeSitter.field(kv, "key")
      val = Noir::TreeSitter.field(kv, "value")
      if key.nil? || val.nil?
        kids = [] of LibTreeSitter::TSNode
        Noir::TreeSitter.each_named_child(kv) { |c| kids << c }
        return {nil, nil} if kids.size < 2
        key ||= kids[0]
        val ||= kids[1]
      end
      {gozero_unwrap(key), gozero_unwrap(val)}
    end

    private def gozero_string_value(node : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(node)
      when "interpreted_string_literal", "raw_string_literal"
        Noir::TreeSitter.node_text(node, source).gsub(/^["`]|["`]$/, "")
      else
        ""
      end
    end

    private def gozero_with_prefix(call : LibTreeSitter::TSNode, source : String) : String?
      function = Noir::TreeSitter.field(call, "function")
      return if function.nil?
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"
      fname = Noir::TreeSitter.field(function, "field")
      return if fname.nil?
      return unless Noir::TreeSitter.node_text(fname, source) == "WithPrefix"
      args = Noir::TreeSitter.field(call, "arguments")
      return if args.nil?
      Noir::TreeSitter.each_named_child(args) do |arg|
        s = gozero_string_value(arg, source)
        return s unless s.empty?
      end
      nil
    end
  end
end
