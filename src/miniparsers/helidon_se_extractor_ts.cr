require "../utils/url_path"
require "../ext/tree_sitter/tree_sitter"
require "./java_callee_extractor"
require "./java_route_extractor_ts"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed walker for Helidon SE's functional routing DSL.
  #
  # Helidon SE has two route-registration shapes that both have to be
  # covered:
  #
  #   1. Inline verb calls directly on a `HttpRouting.Builder` /
  #      `HttpRules` receiver: `routing.get("/x", (req, res) -> ...)`,
  #      chained or nested inside a lambda passed to `.routing(...)`.
  #   2. Modular services: a class `implements HttpService` overrides
  #      `routing(HttpRules rules)` with its own verb calls, and is
  #      mounted elsewhere via `someBuilder.register("/prefix", new
  #      MyService())`. The quickstart/example apps published by the
  #      Helidon project overwhelmingly use this shape — `Main`
  #      composes routing by registering one `HttpService` per
  #      resource, in a totally separate class (often a separate
  #      file).
  #
  # Shape 2 is genuinely cross-class (and often cross-file), so this
  # extractor does not try to resolve the full prefix here. Instead it
  # reports, per file:
  #
  #   * `routes`  — every verb call found, tagged with the *simple*
  #     name of its immediately enclosing class (empty prefix).
  #   * `edges`   — every `.register(prefix, new Target())` call
  #     found, tagged with the enclosing class that issued the call
  #     and the (simple) class name of the target service.
  #
  # The analyzer aggregates `routes`/`edges` across every Helidon file
  # in a project root and resolves the prefix graph there (classes are
  # matched by simple name, project-root scoped — the same
  # approximation `TreeSitterMicronautExtractor`'s interface-route
  # index and `TreeSitterJvmLambdaDslExtractor`'s method-reference
  # index already make).
  module TreeSitterHelidonSeExtractor
    extend self

    # Helidon's fluent verb API: `HttpRules`/`HttpRouting.Builder` both
    # expose the same method names. `any` matches every HTTP method —
    # kept as the literal "ANY" verb, same convention as Ring/Compojure/
    # Pedestal/Wisp/Cowboy in this codebase rather than exploding it into
    # one endpoint per concrete verb.
    VERB_METHODS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      "patch"   => "PATCH",
      "trace"   => "TRACE",
      "any"     => "ANY",
    }

    struct Route
      getter class_name : String
      getter verb : String
      getter path : String
      getter line : Int32
      getter query_params : Array(String)
      getter header_params : Array(String)
      getter cookie_params : Array(String)
      getter body_type : String?
      getter? has_body : Bool
      # 1-hop callees out of the handler body; `path` is attached by the
      # analyzer. Each tuple is (callee_name, line_1_based).
      getter callees : Array(Tuple(String, Int32))
      getter protocol : String

      def initialize(@class_name, @verb, @path, @line, @query_params, @header_params,
                     @cookie_params, @body_type, @has_body, @callees, @protocol = "http")
      end
    end

    # `someBuilder.register(prefix, new Target())` (or the no-prefix
    # `register(new Target())` overload, where `prefix` is `""`).
    # `source_class` is the simple name of the class the `.register`
    # call is lexically inside; `target_class` is the simple name of the
    # mounted `HttpService`.
    struct RegisterEdge
      getter source_class : String
      getter prefix : String
      getter target_class : String

      def initialize(@source_class, @prefix, @target_class)
      end
    end

    struct FileResult
      getter routes : Array(Route)
      getter edges : Array(RegisterEdge)

      def initialize(@routes, @edges)
      end
    end

    def extract(source : String, *, include_callees : Bool = false) : FileResult
      routes = [] of Route
      edges = [] of RegisterEdge

      Noir::TreeSitter.parse_java(source) do |root|
        constants = TreeSitterJavaRouteExtractor.extract_string_constants_from(root, source)
        method_bodies = method_body_index(root, source)
        walk(root, source, "", constants, method_bodies, routes, edges, 0, include_callees)
      end

      FileResult.new(routes, edges)
    end

    # Helidon path-parameter syntax: `{name}`, `{name:regex}` (typed /
    # regex-constrained segment) and `{+name}` (matches multiple path
    # segments). All three name the same logical parameter — normalize
    # down to the plain `{name}` the rest of noir (and the shared
    # path-parameter optimizer pass) expects.
    def normalize_path(path : String) : String
      path.gsub(/\{\+?([^{}:]+)(?::[^{}]*)?\}/) { "{#{$~[1].strip}}" }
    end

    # ---- traversal ----------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode,
                     source : String,
                     current_class : String,
                     constants : Hash(String, String),
                     method_bodies : Hash(String, LibTreeSitter::TSNode),
                     routes : Array(Route),
                     edges : Array(RegisterEdge),
                     depth : Int32,
                     include_callees : Bool)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "class_declaration"
        name = type_identifier_text(node, source)
        new_class = name.empty? ? current_class : name
        Noir::TreeSitter.each_named_child(node) do |child|
          walk(child, source, new_class, constants, method_bodies, routes, edges, depth + 1, include_callees)
        end
        return
      end

      if ty == "method_invocation"
        name = method_invocation_method_name(node, source)
        if verb = VERB_METHODS[name]?
          emit_route(node, source, verb, current_class, constants, method_bodies, routes, include_callees)
        elsif name == "register"
          emit_register_edges(node, source, current_class, constants, edges)
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, current_class, constants, method_bodies, routes, edges, depth + 1, include_callees)
      end
    end

    # `routing.get("/x", handler)` / `rules.get("/x", handler)`. Requires
    # a resolvable string path plus a second (handler) argument — this
    # is what tells a genuine route call apart from unrelated 1-arg
    # `.get(...)` calls that collide on method name (`Optional#get()`,
    # `Map#get(key)`, `List#get(index)`): those never carry a string
    # literal first argument *and* a second argument at the same time.
    private def emit_route(call : LibTreeSitter::TSNode,
                           source : String,
                           verb : String,
                           current_class : String,
                           constants : Hash(String, String),
                           method_bodies : Hash(String, LibTreeSitter::TSNode),
                           routes : Array(Route),
                           include_callees : Bool)
      args = argument_list_node(call)
      return unless args
      return if LibTreeSitter.ts_node_named_child_count(args) < 2

      path_arg = first_string_argument(call, source, constants)
      return unless path_arg

      full_path = normalize_path(path_arg)
      line = Noir::TreeSitter.node_start_row(call)

      query_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      body_type : String? = nil
      has_body = false
      callees = [] of Tuple(String, Int32)

      body = lambda_body_in_args(call) || method_reference_body_in_args(call, source, method_bodies)
      if body
        scan_handler(body, source, 0) do |kind, value|
          case kind
          when :query  then query_params << value
          when :header then header_params << value
          when :cookie then cookie_params << value
          when :body   then has_body = true
          when :body_typed
            body_type = value
            has_body = true
          end
        end

        if include_callees
          Noir::JavaCalleeExtractor.callees_in_lambda(body, source, "").each do |entry|
            name, _path, line_no = entry
            callees << {name, line_no}
          end
        end
      end

      routes << Route.new(current_class, verb, full_path, line, query_params, header_params,
        cookie_params, body_type, has_body, callees)
    end

    # `builder.register("/prefix", new Service())`,
    # `builder.register(new Service())`, and the multi-service overloads
    # (`register(prefix, new A(), new B())`). Any argument the extractor
    # can't resolve to a concrete `HttpService` type (a bare identifier,
    # a lambda/method-reference supplier, …) is silently skipped — the
    # dominant real-world shape is `new ServiceClass(...)` and that's
    # what's covered here.
    private def emit_register_edges(call : LibTreeSitter::TSNode,
                                    source : String,
                                    current_class : String,
                                    constants : Hash(String, String),
                                    edges : Array(RegisterEdge))
      args = argument_list_node(call)
      return unless args

      children = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |child| children << child }
      return if children.empty?

      prefix = ""
      service_children = children
      if Noir::TreeSitter.node_type(children[0]) == "string_literal"
        if resolved = resolve_string_value(children[0], source, constants)
          prefix = resolved
          service_children = children[1..]
        end
      end

      service_children.each do |arg|
        next unless target = service_class_name(arg, source)
        edges << RegisterEdge.new(current_class, prefix, target)
      end
    end

    private def service_class_name(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "object_creation_expression"
        type_node = Noir::TreeSitter.field(node, "type")
        return unless type_node
        simple_type_name(Noir::TreeSitter.node_text(type_node, source))
      when "method_reference"
        text = Noir::TreeSitter.node_text(node, source)
        return unless text.ends_with?("::new")
        simple_type_name(text[0...-5])
      end
    end

    private def simple_type_name(text : String) : String?
      name = text.strip
      return if name.empty?
      if lt = name.index('<')
        name = name[...lt].strip
      end
      if dot = name.rindex('.')
        name = name[(dot + 1)..]
      end
      name.empty? ? nil : name
    end

    # ---- handler-body parameter scan -----------------------------------

    # Helidon's request accessors nest one level deeper than Javalin's
    # flat `ctx.xxxParam(...)` — `req.query().get("name")`,
    # `req.headers().cookies().get("name")`,
    # `req.headers().get(HeaderNames.create("Name"))`,
    # `req.content().as(Foo.class)`. Matched structurally on the
    # *receiver* chain's tail call name rather than a fixed variable
    # name, so it survives whatever the request parameter is called.
    private def scan_handler(node : LibTreeSitter::TSNode,
                             source : String,
                             depth : Int32,
                             &block : Symbol, String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "method_invocation"
        name = method_invocation_method_name(node, source)
        receiver = Noir::TreeSitter.field(node, "object")

        if receiver && QUERY_ACCESSORS.includes?(name) && chain_tail?(receiver, source, "query")
          if value = first_string_argument(node, source, EMPTY_CONSTANTS)
            block.call(:query, value)
          end
        elsif receiver && COOKIE_ACCESSORS.includes?(name) && chain_tail?(receiver, source, "cookies")
          if value = first_string_argument(node, source, EMPTY_CONSTANTS)
            block.call(:cookie, value)
          end
        elsif receiver && HEADER_ACCESSORS.includes?(name) && chain_tail?(receiver, source, "headers")
          if value = header_name_argument(node, source)
            block.call(:header, value)
          end
        elsif receiver && name == "as" && chain_tail?(receiver, source, "content")
          if type = first_class_literal_type(node, source)
            block.call(:body_typed, type)
          else
            block.call(:body, "")
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler(child, source, depth + 1, &block)
      end
    end

    EMPTY_CONSTANTS  = {} of String => String
    QUERY_ACCESSORS  = Set{"get", "first", "all", "contains"}
    COOKIE_ACCESSORS = Set{"get", "first", "all", "getAll", "contains"}
    HEADER_ACCESSORS = Set{"get", "first", "value", "contains"}

    # True when `node` is (or ends in) a zero-arg call named `method` —
    # i.e. `node`'s own text is `<...>.method()` or bare `method()`.
    # Used to confirm `req.query().get(...)` / `req.headers().cookies()
    # .get(...)` / `req.content().as(...)` without caring what the
    # request variable itself is named.
    private def chain_tail?(node : LibTreeSitter::TSNode, source : String, method : String) : Bool
      return false unless Noir::TreeSitter.node_type(node) == "method_invocation"
      Noir::TreeSitter.node_text(node, source).ends_with?(".#{method}()") ||
        Noir::TreeSitter.node_text(node, source) == "#{method}()"
    end

    # `req.headers().get(HeaderNames.create("Name"))` — the header-name
    # argument is a typed `HeaderName`, not a raw string. Known
    # constants (`HeaderNames.CONTENT_TYPE`, …) can't be resolved to
    # their literal wire name without a lookup table, so only the
    # explicit `HeaderNames.create("...")` / `HeaderNames.createFromLowercase("...")`
    # constructor form is supported.
    private def header_name_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "method_invocation"
        name = method_invocation_method_name(arg, source)
        next unless name == "create" || name == "createFromLowercase"
        if value = first_string_argument(arg, source, EMPTY_CONSTANTS)
          return value
        end
      end
      nil
    end

    private def first_class_literal_type(call : LibTreeSitter::TSNode, source : String) : String?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "class_literal"
        Noir::TreeSitter.each_named_child(arg) do |child|
          if Noir::TreeSitter.node_type(child) == "type_identifier"
            return Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      nil
    end

    # ---- shared shape helpers (Java call/string plumbing) --------------
    #
    # These mirror the equivalent private helpers in
    # `TreeSitterJvmLambdaDslExtractor` — Crystal's `private def` is
    # file-scoped, so they can't be shared directly; kept minimal since
    # Helidon has no `nest`/`crud`/router-receiver concepts to carry.

    private def method_invocation_method_name(call : LibTreeSitter::TSNode, source : String) : String
      if name_node = Noir::TreeSitter.field(call, "name")
        return Noir::TreeSitter.node_text(name_node, source)
      end

      result = ""
      Noir::TreeSitter.each_named_child(call) do |child|
        ty = Noir::TreeSitter.node_type(child)
        case ty
        when "identifier"
          result = Noir::TreeSitter.node_text(child, source)
        when "argument_list"
          break
        end
      end
      result
    end

    private def type_identifier_text(decl : LibTreeSitter::TSNode, source : String) : String
      name_node = Noir::TreeSitter.field(decl, "name")
      return "" unless name_node
      Noir::TreeSitter.node_text(name_node, source)
    end

    private def argument_list_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "argument_list"
      end
      nil
    end

    private def first_string_argument(call : LibTreeSitter::TSNode,
                                      source : String,
                                      constants : Hash(String, String)) : String?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string_literal", "identifier", "field_access", "scoped_identifier", "binary_expression", "parenthesized_expression"
          if value = resolve_string_value(arg, source, constants)
            return value
          end
        end
      end
      nil
    end

    private def resolve_string_value(node : LibTreeSitter::TSNode,
                                     source : String,
                                     constants : Hash(String, String),
                                     depth = 0) : String?
      return if depth > 16

      case Noir::TreeSitter.node_type(node)
      when "string_literal"
        decode_string_literal(node, source)
      when "identifier", "field_access", "scoped_identifier"
        resolve_constant_reference(Noir::TreeSitter.node_text(node, source), constants)
      when "binary_expression"
        return unless Noir::TreeSitter.node_text(node, source).includes?("+")
        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        return unless left && right
        left_value = resolve_string_value(left, source, constants, depth + 1)
        right_value = resolve_string_value(right, source, constants, depth + 1)
        return unless left_value && right_value
        "#{left_value}#{right_value}"
      when "parenthesized_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          if value = resolve_string_value(child, source, constants, depth + 1)
            return value
          end
        end
      end
    end

    private def resolve_constant_reference(name : String, constants : Hash(String, String)) : String?
      if resolved = constants[name]?
        return resolved
      end

      suffix = ".#{name}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      raw.size >= 2 && raw.starts_with?('"') && raw.ends_with?('"') ? raw[1..-2] : raw
    end

    # Pull the lambda's body (`block` or expression) out of the call's
    # argument list. Returns nil if no lambda is passed.
    private def lambda_body_in_args(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "lambda_expression"
        Noir::TreeSitter.each_named_child(arg) do |child|
          ty = Noir::TreeSitter.node_type(child)
          next if ty == "identifier" || ty == "formal_parameters" || ty == "inferred_parameters"
          return child
        end
      end
      nil
    end

    private def method_reference_body_in_args(call : LibTreeSitter::TSNode,
                                              source : String,
                                              method_bodies : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      args = argument_list_node(call)
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "method_reference"

        method_name = Noir::TreeSitter.node_text(arg, source).split("::").last?.to_s
        next if method_name.empty?

        if body = method_bodies[method_name]?
          return body
        end
      end

      nil
    end

    private def method_body_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      bodies = Hash(String, LibTreeSitter::TSNode).new

      walk_method_declarations(root) do |method|
        name_node = Noir::TreeSitter.field(method, "name")
        body = Noir::TreeSitter.field(method, "body")
        next unless name_node && body

        name = Noir::TreeSitter.node_text(name_node, source)
        bodies[name] ||= body
      end

      bodies
    end

    private def walk_method_declarations(node : LibTreeSitter::TSNode, depth : Int32 = 0, &block : LibTreeSitter::TSNode ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "method_declaration"
        block.call(node)
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_method_declarations(child, depth + 1, &block)
      end
    end
  end
end
