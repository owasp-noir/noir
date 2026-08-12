# Part of Noir::TreeSitterGoRouteExtractor: go-restful WebService builder chains.
module Noir
  module TreeSitterGoRouteExtractor
    # go-restful (`github.com/emicklei/go-restful`) routes. Each WebService
    # declares a base `ws.Path("/users")` and registers routes as a nested
    # builder chain: `ws.Route(ws.GET("/{id}").To(h).Param(ws.PathParameter(
    # "id", ...)).Reads(User{}))`. The verb and sub-path live on the inner
    # `ws.GET(...)` call; the full path is the WebService's `Path()` prefix
    # joined with it; params are self-declared on the chain (`PathParameter`/
    # `QueryParameter`/`HeaderParameter`/`BodyParameter`/`FormParameter`) plus
    # `Reads(struct)` for the JSON body. `handler` carries the `.To(...)`
    # argument for callee wiring.
    struct RestfulRoute
      getter verb : String
      getter path : String
      getter handler : String
      getter line : Int32
      getter params : Array(Tuple(String, String)) # (name, in: path/query/header/json/form)

      def initialize(@verb, @path, @handler, @line, @params)
      end
    end

    RESTFUL_VERBS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]

    RESTFUL_PARAM_KINDS = {
      "PathParameter"   => "path",
      "QueryParameter"  => "query",
      "HeaderParameter" => "header",
      "BodyParameter"   => "json",
      "FormParameter"   => "form",
    }

    def extract_go_restful_routes(source : String) : Array(RestfulRoute)
      results = [] of RestfulRoute
      Noir::TreeSitter.parse_go(source) do |root|
        # Pass 1: map each WebService variable to its `Path("/prefix")`. The
        # call may be chained (`ws.Path("/x").Consumes(...).Produces(...)`),
        # but the `Path` selector's operand is still the bare ws identifier.
        prefixes = Hash(String, String).new
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          fn = Noir::TreeSitter.field(node, "function")
          next if fn.nil? || Noir::TreeSitter.node_type(fn) != "selector_expression"
          field = Noir::TreeSitter.field(fn, "field")
          next if field.nil? || Noir::TreeSitter.node_text(field, source) != "Path"
          operand = Noir::TreeSitter.field(fn, "operand")
          next if operand.nil? || Noir::TreeSitter.node_type(operand) != "identifier"
          if value = chi_first_string_arg(node, source)
            prefixes[Noir::TreeSitter.node_text(operand, source)] = value
          end
        end

        # Pass 2: every `<ws>.Route(<ws>.VERB("/sub")…)` registration.
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          fn = Noir::TreeSitter.field(node, "function")
          next if fn.nil? || Noir::TreeSitter.node_type(fn) != "selector_expression"
          field = Noir::TreeSitter.field(fn, "field")
          next if field.nil? || Noir::TreeSitter.node_text(field, source) != "Route"
          args = Noir::TreeSitter.field(node, "arguments")
          next if args.nil?
          builder = nil
          Noir::TreeSitter.each_named_child(args) do |arg|
            builder ||= arg if Noir::TreeSitter.node_type(arg) == "call_expression"
          end
          next if builder.nil?
          if route = decode_restful_builder(builder, source, prefixes, Noir::TreeSitter.node_start_row(node))
            results << route
          end
        end
      end
      results
    end

    # Peel a go-restful builder chain (`ws.GET("/x").To(h).Param(…).Reads(…)`)
    # from the outside in: the deepest call is the verb (`ws.GET("/x")`), the
    # intermediate `.Param(…)`/`.Reads(…)` calls carry the params, and the
    # verb's operand identifier selects the WebService `Path()` prefix.
    private def decode_restful_builder(builder : LibTreeSitter::TSNode,
                                       source : String,
                                       prefixes : Hash(String, String),
                                       line : Int32) : RestfulRoute?
      verb = nil
      sub_path = ""
      ws_var = nil
      handler = ""
      params = [] of Tuple(String, String)

      cur = builder
      while Noir::TreeSitter.node_type(cur) == "call_expression"
        call_fn = Noir::TreeSitter.field(cur, "function")
        break if call_fn.nil? || Noir::TreeSitter.node_type(call_fn) != "selector_expression"
        method_field = Noir::TreeSitter.field(call_fn, "field")
        break if method_field.nil?
        method_name = Noir::TreeSitter.node_text(method_field, source)

        if RESTFUL_VERBS.includes?(method_name)
          verb = method_name
          sub_path = chi_first_string_arg(cur, source) || ""
          operand = Noir::TreeSitter.field(call_fn, "operand")
          ws_var = Noir::TreeSitter.node_text(operand, source) if operand && Noir::TreeSitter.node_type(operand) == "identifier"
          break
        elsif method_name == "To"
          handler = restful_first_arg_text(cur, source) if handler.empty?
        elsif method_name == "Param"
          if p = decode_restful_param(cur, source)
            params << p
          end
        elsif method_name == "Reads"
          params << {"body", "json"} unless params.any? { |n, _| n == "body" }
        end

        operand = Noir::TreeSitter.field(call_fn, "operand")
        break if operand.nil?
        cur = operand
      end

      v = verb
      return if v.nil?

      # The chain is peeled outside-in, so params come out in reverse source
      # order — flip them back so they read as written.
      params.reverse!

      prefix = ws_var.try { |name| prefixes[name]? } || ""
      full = if sub_path.empty?
               # `ws.POST("")` registers the route at the WebService root —
               # the prefix itself, with no trailing slash.
               prefix.empty? ? "/" : prefix
             elsif prefix.empty?
               sub_path
             else
               group_join(prefix, sub_path)
             end
      full = "/#{full}" unless full.starts_with?("/")
      RestfulRoute.new(v, full, handler, line, params)
    end

    # `ws.Param(ws.PathParameter("user-id", "desc")…)` — the arg is itself a
    # `ws.<Kind>Parameter("name", …)` builder; pull the kind and the name.
    private def decode_restful_param(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String)?
      args = Noir::TreeSitter.field(call, "arguments")
      return if args.nil?
      inner = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        inner ||= arg if Noir::TreeSitter.node_type(arg) == "call_expression"
      end
      # Peel an outer chain on the parameter builder
      # (`ws.PathParameter("id", "").DataType("integer")`) to its base call.
      node = inner
      while node && Noir::TreeSitter.node_type(node) == "call_expression"
        call_fn = Noir::TreeSitter.field(node, "function")
        break if call_fn.nil? || Noir::TreeSitter.node_type(call_fn) != "selector_expression"
        field = Noir::TreeSitter.field(call_fn, "field")
        break if field.nil?
        kind = Noir::TreeSitter.node_text(field, source)
        if param_in = RESTFUL_PARAM_KINDS[kind]?
          name = chi_first_string_arg(node, source)
          return if name.nil? || name.empty?
          return {name, param_in}
        end
        node = Noir::TreeSitter.field(call_fn, "operand")
      end
      nil
    end

    private def restful_first_arg_text(call : LibTreeSitter::TSNode, source : String) : String
      args = Noir::TreeSitter.field(call, "arguments")
      return "" if args.nil?
      Noir::TreeSitter.each_named_child(args) do |arg|
        return Noir::TreeSitter.node_text(arg, source)
      end
      ""
    end
  end
end
