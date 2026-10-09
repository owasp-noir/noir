require "../ext/tree_sitter/tree_sitter"
require "../utils/url_path"

module Noir
  # Contract-first TypeScript routers, where routes are declared as data
  # (a contract object or a builder chain) rather than as `app.get(...)`
  # calls:
  #
  # ```
  # // ts-rest
  # c.router({ getPost: { method: 'GET', path: '/posts/:id' } }, { pathPrefix: '/api' })
  # // oRPC
  # os.route({ method: 'GET', path: '/planets/{id}' }).input(z.object({ id: z.number() }))
  # // Effect HttpApi
  # HttpApiGroup.make("users").add(HttpApiEndpoint.get("findById", "/users/:id")).prefix("/v1")
  # ```
  #
  # Zod `z.object({...})` / Effect `Schema.Struct({...})` keys are read as
  # the request fields. Top-level declarations referenced from another
  # router (`posts: postsContract`, `.add(UsersGroup)`) are resolved within
  # the file so the outer prefix applies, and are then not reported on
  # their own a second time.
  #
  # ponytail: same-file resolution only; a router assembled from imported
  # sub-routers reports each one under its own prefix. Follow imports via
  # `ImportGraph` if that turns out common.
  module TSContractExtractor
    extend self

    class Route
      property path : String
      getter method : String
      # 1-based.
      getter line : Int32
      # {name, param_type}
      getter params = [] of Tuple(String, String)

      def initialize(@method : String, @path : String, @line : Int32)
      end

      def add_fields(names : Array(String), type : String)
        names.each { |name| @params << {name, type} unless path_param?(name) }
      end

      private def path_param?(name : String) : Bool
        @path.includes?(":#{name}") || @path.includes?("{#{name}}")
      end
    end

    private class Context
      getter source : String
      getter decls = {} of String => LibTreeSitter::TSNode
      getter used = Set(String).new
      @active = Set(String).new

      def initialize(@source : String)
      end

      # Yields a top-level declaration's value, marking it as consumed by
      # an outer router. Re-entry on a cycle (`a = c.router({ b: a })`) is
      # skipped.
      def resolve(name : String, & : LibTreeSitter::TSNode -> Array(Route)) : Array(Route)
        node = @decls[name]?
        return [] of Route if node.nil? || @active.includes?(name)
        @used << name
        @active << name
        begin
          yield node
        ensure
          @active.delete(name)
        end
      end
    end

    # The JavaScript grammar reads `os.$context<{ a: B }>()` and
    # `Schema.Class<User>("User")` as comparisons, which derails the whole
    # call chain. Blank generic arguments in front of a call, keeping
    # every line where it was.
    GENERIC_ARGS = /(?<=[\w$])<(?:[^<>()\n;]|<[^<>()\n;]*>)*>(?=\s*\()/

    SCHEMA_OBJECT_CALLS = Set{"object", "strictObject", "looseObject", "Struct"}
    QUERY_METHODS       = Set{"GET", "HEAD"}
    EFFECT_VERBS        = {
      "get" => "GET", "post" => "POST", "put" => "PUT", "patch" => "PATCH",
      "del" => "DELETE", "delete" => "DELETE", "head" => "HEAD", "options" => "OPTIONS",
    }
    EFFECT_FIELDS        = {"setPayload" => "payload", "setUrlParams" => "query", "setHeaders" => "header"}
    EFFECT_OPTION_FIELDS = {"payload" => "payload", "urlParams" => "query", "headers" => "header"}
    TS_REST_FIELDS       = {"body" => "json", "query" => "query", "headers" => "header"}

    # --- ts-rest -----------------------------------------------------------

    def ts_rest(source : String) : Array(Route)
      extract(source) { |node, ctx| ts_rest_routes(node, "", ctx) }
    end

    # `<x>.router({ ... }, { pathPrefix })`. The server-side
    # `s.router(contract, impl)` takes an identifier first and is skipped.
    private def ts_rest_routes(node : LibTreeSitter::TSNode, prefix : String, ctx : Context) : Array(Route)
      if (obj = router_call_object(node, ctx))
        prefix = URLPath.join(prefix, object_string(second_arg(node), "pathPrefix", ctx) || "")
        return ts_rest_entries(obj, prefix, ctx)
      end
      descend(node) { |child| ts_rest_routes(child, prefix, ctx) }
    end

    private def ts_rest_entries(obj : LibTreeSitter::TSNode, prefix : String, ctx : Context) : Array(Route)
      routes = [] of Route
      each_pair(obj, ctx) { |_, value, pair| routes.concat(ts_rest_entry(value, pair, prefix, ctx)) }
      routes
    end

    private def ts_rest_entry(value : LibTreeSitter::TSNode, pair : LibTreeSitter::TSNode, prefix : String, ctx : Context) : Array(Route)
      case TreeSitter.node_type(value)
      when "object"
        method = object_string(value, "method", ctx)
        path = object_string(value, "path", ctx)
        # A plain nested object is a sub-router too.
        return ts_rest_entries(value, prefix, ctx) unless method && path

        route = Route.new(method.upcase, URLPath.join(prefix, path), TreeSitter.node_start_row(pair) + 1)
        each_pair(value, ctx) do |key, field_value|
          TS_REST_FIELDS[key]?.try { |type| route.add_fields(schema_fields(field_value, ctx), type) }
        end
        [route]
      when "identifier", "shorthand_property_identifier"
        ctx.resolve(text(value, ctx)) { |decl| ts_rest_entry(decl, pair, prefix, ctx) }
      when "call_expression"
        # Nested `c.router(...)`, or the older `c.query({...})` /
        # `c.mutation({...})` wrappers around a route object.
        if router_call_object(value, ctx)
          ts_rest_routes(value, prefix, ctx)
        elsif (arg = first_arg(value)) && TreeSitter.node_type(arg) == "object"
          ts_rest_entry(arg, pair, prefix, ctx)
        else
          [] of Route
        end
      else
        [] of Route
      end
    end

    private def router_call_object(node : LibTreeSitter::TSNode, ctx : Context) : LibTreeSitter::TSNode?
      return unless call_property(node, ctx) == "router"
      arg = first_arg(node)
      arg if arg && TreeSitter.node_type(arg) == "object"
    end

    # --- oRPC --------------------------------------------------------------

    def orpc(source : String) : Array(Route)
      extract(source) { |node, ctx| orpc_routes(node, "", ctx) }
    end

    # A procedure chain carrying `.route({ path })`, in any link order
    # (`os.input(...).route(...)` is as valid as the reverse). Procedures
    # without `.route()` are RPC-only and not reported. `.router({...})`
    # applies the chain's `.prefix('/x')` to every procedure it holds.
    private def orpc_routes(node : LibTreeSitter::TSNode, prefix : String, ctx : Context) : Array(Route)
      links = chain_links(node, ctx)
      if (route_call = links.find { |l| l[0] == "route" }) && (config = first_arg(route_call[1]))
        if TreeSitter.node_type(config) == "object" && (path = object_string(config, "path", ctx))
          method = (object_string(config, "method", ctx) || "POST").upcase
          route = Route.new(method, URLPath.join(prefix, path), TreeSitter.call_name_row(route_call[1]) + 1)
          links.find { |l| l[0] == "input" }.try do |input|
            first_arg(input[1]).try { |schema| route.add_fields(schema_fields(schema, ctx), QUERY_METHODS.includes?(method) ? "query" : "json") }
          end
          return [route]
        end
      end

      if (router = links.find { |l| l[0] == "router" }) && (obj = router_call_object(router[1], ctx))
        links.find { |l| l[0] == "prefix" }.try do |link|
          first_arg(link[1]).try { |arg| string_value(arg, ctx).try { |p| prefix = URLPath.join(prefix, p) } }
        end
        return orpc_entries(obj, prefix, ctx)
      end

      descend(node) { |child| orpc_routes(child, prefix, ctx) }
    end

    private def orpc_entries(obj : LibTreeSitter::TSNode, prefix : String, ctx : Context) : Array(Route)
      routes = [] of Route
      each_pair(obj, ctx) do |_, value|
        routes.concat(
          case TreeSitter.node_type(value)
          when "identifier", "shorthand_property_identifier"
            ctx.resolve(text(value, ctx)) { |decl| orpc_routes(decl, prefix, ctx) }
          when "object"
            orpc_entries(value, prefix, ctx)
          else
            orpc_routes(value, prefix, ctx)
          end
        )
      end
      routes
    end

    # The links of `a.b(1).c(2)` as {"c", call}, {"b", call}, outermost first.
    private def chain_links(node : LibTreeSitter::TSNode, ctx : Context) : Array(Tuple(String, LibTreeSitter::TSNode))
      links = [] of Tuple(String, LibTreeSitter::TSNode)
      while (property = call_property(node, ctx))
        links << {property, node}
        node = TreeSitter.field(TreeSitter.field(node, "function").not_nil!, "object") || break
      end
      links
    end

    # --- Effect HttpApi ----------------------------------------------------

    def effect(source : String) : Array(Route)
      extract(source) { |node, ctx| effect_routes(node, ctx) }
    end

    # `.prefix(p)` applies to the endpoints already added to its receiver,
    # matching `HttpApiGroup.prefix` / `HttpApi.prefix`; `.add(Group)`
    # resolves a group declared elsewhere in the file.
    private def effect_routes(node : LibTreeSitter::TSNode, ctx : Context) : Array(Route)
      return descend(node) { |child| effect_routes(child, ctx) } unless TreeSitter.node_type(node) == "call_expression"

      function = TreeSitter.field(node, "function").not_nil!
      args = TreeSitter.field(node, "arguments")

      # HttpApiEndpoint.get("remove")`/users/${idParam}`
      if args && TreeSitter.node_type(args) == "template_string" && (method = effect_verb(function, ctx))
        return [Route.new(method, template_path(args, ctx), TreeSitter.call_name_row(function) + 1)]
      end

      if method = effect_verb(node, ctx)
        path = second_arg(node).try { |arg| string_value(arg, ctx) }
        return [] of Route unless path
        route = Route.new(method, path, TreeSitter.call_name_row(node) + 1)
        # The options-object form: get("name", "/path", { payload, urlParams, headers }).
        if (options = args.try { |a| nth_arg(a, 2) }) && TreeSitter.node_type(options) == "object"
          each_pair(options, ctx) do |key, value|
            type = EFFECT_OPTION_FIELDS[key]?
            effect_fields(route, type, value, ctx) if type
          end
        end
        return [route]
      end

      property = call_property(node, ctx)
      return descend(node) { |child| effect_routes(child, ctx) } unless property

      routes = effect_routes(TreeSitter.field(function, "object").not_nil!, ctx)
      added = [] of Route
      each_arg(node) do |arg|
        added.concat(property == "add" && TreeSitter.node_type(arg) == "identifier" ? ctx.resolve(text(arg, ctx)) { |decl| effect_routes(decl, ctx) } : effect_routes(arg, ctx))
      end

      if property == "prefix" && (prefix = first_arg(node).try { |arg| string_value(arg, ctx) })
        routes.each { |route| route.path = URLPath.join(prefix, route.path) }
      elsif (type = EFFECT_FIELDS[property]?) && (schema = first_arg(node))
        routes.each { |route| effect_fields(route, type, schema, ctx) }
      end
      routes + added
    end

    private def effect_fields(route : Route, type : String, schema : LibTreeSitter::TSNode, ctx : Context)
      # Effect sends a GET/HEAD payload as URL search params.
      type = QUERY_METHODS.includes?(route.method) ? "query" : "json" if type == "payload"
      route.add_fields(schema_fields(schema, ctx), type)
    end

    private def effect_verb(call : LibTreeSitter::TSNode, ctx : Context) : String?
      return unless (property = call_property(call, ctx))
      object = TreeSitter.field(TreeSitter.field(call, "function").not_nil!, "object")
      return unless object && text(object, ctx) == "HttpApiEndpoint"
      EFFECT_VERBS[property]?
    end

    # `/users/${idParam}` with `idParam = HttpApiSchema.param("id", ...)`
    # becomes `/users/:id`.
    private def template_path(template : LibTreeSitter::TSNode, ctx : Context) : String
      String.build do |io|
        TreeSitter.each_named_child(template) do |part|
          if TreeSitter.node_type(part) == "template_substitution"
            name = text(part, ctx)[2..-2].strip
            param = ctx.decls[name]?.try { |decl| call_property(decl, ctx) == "param" ? first_arg(decl) : nil }
            io << ':' << (param.try { |p| string_value(p, ctx) } || name)
          else
            io << text(part, ctx)
          end
        end
      end
    end

    # --- shared ------------------------------------------------------------

    # Parses `source` and hands each top-level declaration to `collect`.
    # A declaration another router resolved is dropped from the result, so
    # it is reported once, under the outer router's prefix.
    private def extract(source : String, &collect : LibTreeSitter::TSNode, Context -> Array(Route)) : Array(Route)
      result = [] of Route
      return result if source.empty?

      normalized = source.gsub(GENERIC_ARGS) { |m| " " * m.size }
      TreeSitter.parse_javascript(normalized) do |root|
        ctx = Context.new(normalized)
        roots = [] of Tuple(String?, LibTreeSitter::TSNode)
        each_top_level(root, ctx) do |name, node|
          ctx.decls[name] = node if name
          roots << {name, node}
        end
        roots.map { |name, node| {name, collect.call(node, ctx)} }.each do |name, routes|
          result.concat(routes) unless name && ctx.used.includes?(name)
        end
      end
      result
    end

    private def each_top_level(root : LibTreeSitter::TSNode, ctx : Context, &)
      TreeSitter.each_named_child(root) do |stmt|
        if TreeSitter.node_type(stmt) == "export_statement"
          stmt = TreeSitter.field(stmt, "declaration") || TreeSitter.field(stmt, "value") || stmt
        end
        case TreeSitter.node_type(stmt)
        when "lexical_declaration", "variable_declaration"
          TreeSitter.each_named_child(stmt) do |declarator|
            name = TreeSitter.field(declarator, "name")
            value = TreeSitter.field(declarator, "value")
            next unless name && value
            yield (TreeSitter.node_type(name) == "identifier" ? text(name, ctx) : nil), value
          end
        when "class_declaration"
          yield TreeSitter.field(stmt, "name").try { |n| text(n, ctx) }, stmt
        else
          yield nil, stmt
        end
      end
    end

    # Field names of a `z.object({...})` / `Schema.Struct({...})` schema,
    # looking through modifier chains (`.strict()`, `.optional()`),
    # `.extend` / `.omit` / `.pick({...})` and same-file schema constants.
    private def schema_fields(node : LibTreeSitter::TSNode, ctx : Context, depth : Int32 = 0) : Array(String)
      fields = [] of String
      return fields if depth > 8

      case TreeSitter.node_type(node)
      when "object"
        each_pair(node, ctx) { |key| fields << key }
      when "identifier"
        ctx.decls[text(node, ctx)]?.try { |decl| fields = schema_fields(decl, ctx, depth + 1) }
      when "call_expression"
        property = call_property(node, ctx)
        arg = first_arg(node)
        if property && SCHEMA_OBJECT_CALLS.includes?(property)
          fields = schema_fields(arg, ctx, depth + 1) if arg && TreeSitter.node_type(arg) == "object"
        elsif property
          fields = schema_fields(TreeSitter.field(TreeSitter.field(node, "function").not_nil!, "object").not_nil!, ctx, depth + 1)
          if arg && TreeSitter.node_type(arg) == "object"
            case property
            when "extend" then fields.concat(schema_fields(arg, ctx, depth + 1))
            when "omit"   then fields -= schema_fields(arg, ctx, depth + 1)
            when "pick"   then fields &= schema_fields(arg, ctx, depth + 1)
            end
          end
        end
      end
      fields
    end

    private def each_pair(obj : LibTreeSitter::TSNode, ctx : Context, &)
      TreeSitter.each_named_child(obj) do |pair|
        case TreeSitter.node_type(pair)
        when "pair"
          key = TreeSitter.field(pair, "key")
          value = TreeSitter.field(pair, "value")
          next unless key && value
          name = TreeSitter.node_type(key) == "string" ? string_value(key, ctx) : text(key, ctx)
          yield name, value, pair if name
        when "shorthand_property_identifier"
          yield text(pair, ctx), pair, pair
        end
      end
    end

    private def object_string(obj : LibTreeSitter::TSNode?, key : String, ctx : Context) : String?
      return unless obj && TreeSitter.node_type(obj) == "object"
      each_pair(obj, ctx) { |name, value| return string_value(value, ctx) if name == key }
      nil
    end

    # A quoted or substitution-free backtick literal.
    private def string_value(node : LibTreeSitter::TSNode, ctx : Context) : String?
      case TreeSitter.node_type(node)
      when "string"
        raw = text(node, ctx)
        raw.size >= 2 ? raw[1..-2] : nil
      when "template_string"
        raw = text(node, ctx)
        raw[1..-2] unless raw.includes?("${")
      end
    end

    # `x.name(...)` → "name".
    private def call_property(node : LibTreeSitter::TSNode, ctx : Context) : String?
      return unless TreeSitter.node_type(node) == "call_expression"
      function = TreeSitter.field(node, "function")
      return unless function && TreeSitter.node_type(function) == "member_expression"
      TreeSitter.field(function, "property").try { |p| text(p, ctx) }
    end

    private def first_arg(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      TreeSitter.field(call, "arguments").try { |args| nth_arg(args, 0) }
    end

    private def second_arg(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      TreeSitter.field(call, "arguments").try { |args| nth_arg(args, 1) }
    end

    private def nth_arg(args : LibTreeSitter::TSNode, n : Int32) : LibTreeSitter::TSNode?
      return unless TreeSitter.node_type(args) == "arguments"
      i = 0
      TreeSitter.each_named_child(args) do |arg|
        return arg if i == n
        i += 1
      end
      nil
    end

    private def each_arg(call : LibTreeSitter::TSNode, &)
      args = TreeSitter.field(call, "arguments")
      return unless args && TreeSitter.node_type(args) == "arguments"
      TreeSitter.each_named_child(args) { |arg| yield arg }
    end

    private def descend(node : LibTreeSitter::TSNode, & : LibTreeSitter::TSNode -> Array(Route)) : Array(Route)
      routes = [] of Route
      TreeSitter.each_named_child(node) { |child| routes.concat(yield child) }
      routes
    end

    private def text(node : LibTreeSitter::TSNode, ctx : Context) : String
      TreeSitter.node_text(node, ctx.source)
    end
  end
end
