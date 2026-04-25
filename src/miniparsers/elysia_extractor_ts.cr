require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed Elysia extractor.
  #
  # Elysia uses a chained-method DSL similar to Hono / Itty:
  #
  # ```
  # const app = new Elysia()
  #     .get('/users', () => ...)
  #     .post('/users', ({ body }) => body)
  #     .get('/users/:id', ({ params }) => params.id)
  #     .group('/api/v1', (app) =>
  #         app
  #             .get('/health', () => 'ok')
  #             .post('/submit', ({ body }) => body)
  #     )
  #     .listen(3000)
  # ```
  #
  # Recognised:
  #
  #   * Verb methods on any chain receiver: `.get` `.post` `.put`
  #     `.delete` `.patch` `.head` `.options` `.all` (the wildcard
  #     verb fans out to GET/POST/PUT/DELETE/PATCH).
  #   * `.group(prefix, fn)` — `fn`'s body is walked with the
  #     prefix joined onto the surrounding scope.
  #   * `.guard(opts, fn)` and `.use(plugin)` — pass-through
  #     wrappers; descend the inner body without changing prefix.
  #   * Handler-body scanning for `query.X`, `headers.X`,
  #     `cookie.X`, and bare `body` access. `params.X` is
  #     intentionally skipped — the URL placeholder already gives
  #     the path Param via the optimizer. Receiver name isn't
  #     enforced (`(ctx) => ctx.query.foo`,
  #     `({ query }) => query.foo`, and even `(c) => c.query.foo`
  #     all surface signals).
  #
  # Out of scope for this first cut:
  #
  #   * `.use(somePlugin)` doesn't follow into the plugin file —
  #     plugin-defined routes need cross-file resolution.
  #   * Typed schema (`{ body: t.Object({...}) }`) constraint
  #     synthesis. The `body` Param is emitted but its `value`
  #     stays empty (the schema is a typebox literal).
  #   * `.derive` / `.state` / `.decorate` are pass-through
  #     wrappers conceptually but none of them register routes —
  #     skipping them also skips any inner verb calls. Real-world
  #     usage rarely puts routes inside these blocks.
  module TreeSitterElysiaExtractor
    extend self

    HTTP_VERB_METHODS = {
      "get"     => "GET",
      "post"    => "POST",
      "put"     => "PUT",
      "delete"  => "DELETE",
      "patch"   => "PATCH",
      "head"    => "HEAD",
      "options" => "OPTIONS",
      "trace"   => "TRACE",
      "connect" => "CONNECT",
    }

    ALL_VERBS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    GROUP_METHODS       = Set{"group"}
    TRANSPARENT_METHODS = Set{"guard", "use"}

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32
      getter? has_body : Bool
      getter query_params : Array(String)
      getter header_params : Array(String)
      getter cookie_params : Array(String)

      def initialize(@verb, @path, @line, @has_body,
                     @query_params, @header_params, @cookie_params)
      end
    end

    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_javascript(source) do |root|
        walk(root, source, "", routes)
      end
      routes
    end

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route))
      if Noir::TreeSitter.node_type(node) == "call_expression"
        method = chain_method_name(node, source)
        case
        when HTTP_VERB_METHODS.has_key?(method)
          emit_route(node, source, HTTP_VERB_METHODS[method], prefix, routes)
          walk_chain_predecessor(node, source, prefix, routes)
          return
        when method == "all"
          ALL_VERBS.each { |verb| emit_route(node, source, verb, prefix, routes) }
          walk_chain_predecessor(node, source, prefix, routes)
          return
        when GROUP_METHODS.includes?(method)
          handle_group(node, source, prefix, routes)
          walk_chain_predecessor(node, source, prefix, routes)
          return
        when TRANSPARENT_METHODS.includes?(method)
          handle_transparent(node, source, prefix, routes)
          walk_chain_predecessor(node, source, prefix, routes)
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, routes)
      end
    end

    # `app.get(...)` parses as `call_expression(member_expression(_,
    # property_identifier))`. Return the property name when that
    # shape matches; an empty string otherwise (e.g., `new Foo()`,
    # `Foo()` — bare identifier callees).
    private def chain_method_name(call : LibTreeSitter::TSNode, source : String) : String
      callee = first_named_child(call)
      return "" unless callee
      return "" unless Noir::TreeSitter.node_type(callee) == "member_expression"
      Noir::TreeSitter.each_named_child(callee) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "property_identifier"
      end
      ""
    end

    # Continue down the chain into the prior link's call_expression
    # — `a.get(...).post(...)` outer has the inner `a.get(...)` as
    # the member_expression's first child.
    private def walk_chain_predecessor(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route))
      callee = first_named_child(call)
      return unless callee
      return unless Noir::TreeSitter.node_type(callee) == "member_expression"
      inner = first_named_child(callee)
      return unless inner
      walk(inner, source, prefix, routes) if Noir::TreeSitter.node_type(inner) == "call_expression"
    end

    private def handle_group(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route))
      args = arguments_node(call)
      return unless args

      group_path : String? = nil
      group_body : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string"
          group_path ||= decode_string(arg, source)
        when "arrow_function"
          group_body ||= arrow_body(arg)
        end
      end
      return unless group_path && group_body

      new_prefix = join_paths(prefix, group_path)
      walk(group_body, source, new_prefix, routes)
    end

    private def handle_transparent(call : LibTreeSitter::TSNode, source : String, prefix : String, routes : Array(Route))
      args = arguments_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "arrow_function"
        if body = arrow_body(arg)
          walk(body, source, prefix, routes)
        end
      end
    end

    private def emit_route(call : LibTreeSitter::TSNode, source : String, verb : String, prefix : String, routes : Array(Route))
      args = arguments_node(call)
      return unless args

      path : String? = nil
      handler : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string"
          path ||= decode_string(arg, source)
        when "arrow_function"
          handler ||= arg
        end
      end
      return unless path

      full_path = join_paths(prefix, path)
      line = Noir::TreeSitter.node_start_row(call)

      query_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      has_body = false

      if handler
        scan_handler(handler, source) do |kind, value|
          case kind
          when :query  then query_params << value unless query_params.includes?(value)
          when :header then header_params << value unless header_params.includes?(value)
          when :cookie then cookie_params << value unless cookie_params.includes?(value)
          when :body   then has_body = true
          end
        end
      end

      routes << Route.new(verb, full_path, line, has_body,
        query_params, header_params, cookie_params)
    end

    # ---- handler-body scan ------------------------------------------

    # Walk the arrow-function (parameters + body) for parameter
    # signals. Both the destructuring pattern
    # (`({ body, query, headers, cookie })`) and member-expression
    # access (`query.foo`, `ctx.headers['x']`) contribute.
    private def scan_handler(handler : LibTreeSitter::TSNode, source : String, &block : Symbol, String ->)
      Noir::TreeSitter.each_named_child(handler) do |child|
        case Noir::TreeSitter.node_type(child)
        when "formal_parameters"
          scan_destructured_params(child, source, &block)
        else
          scan_handler_body(child, source, &block)
        end
      end
    end

    # `({ body, query, params })` style. `body` standalone in the
    # destructure pattern is enough to surface a body Param —
    # Elysia doesn't carry per-field info at the request type, so
    # the body is a single opaque param.
    private def scan_destructured_params(params : LibTreeSitter::TSNode, source : String, &block : Symbol, String ->)
      Noir::TreeSitter.each_named_child(params) do |param|
        next unless Noir::TreeSitter.node_type(param) == "object_pattern"
        Noir::TreeSitter.each_named_child(param) do |entry|
          name = destructure_key_name(entry, source)
          next if name.empty?
          block.call(:body, "") if name == "body"
        end
      end
    end

    private def destructure_key_name(entry : LibTreeSitter::TSNode, source : String) : String
      case Noir::TreeSitter.node_type(entry)
      when "shorthand_property_identifier_pattern", "shorthand_property_identifier", "identifier"
        Noir::TreeSitter.node_text(entry, source)
      when "pair_pattern"
        Noir::TreeSitter.each_named_child(entry) do |child|
          if Noir::TreeSitter.node_type(child) == "property_identifier"
            return Noir::TreeSitter.node_text(child, source)
          end
        end
        ""
      else
        ""
      end
    end

    private def scan_handler_body(node : LibTreeSitter::TSNode, source : String, &block : Symbol, String ->)
      ty = Noir::TreeSitter.node_type(node)

      case ty
      when "member_expression"
        chain = navigation_chain(node, source)
        # The relevant categories appear at any position in the
        # chain — `query.foo` / `ctx.query.foo` / `c.query.foo`
        # all surface foo as a query param.
        idx = chain.index { |seg| seg == "query" || seg == "headers" || seg == "cookie" }
        if idx && idx + 1 < chain.size
          tail = chain[idx + 1]
          unless tail.empty?
            case chain[idx]
            when "query"   then block.call(:query, tail)
            when "headers" then block.call(:header, tail)
            when "cookie"  then block.call(:cookie, tail)
            end
          end
        elsif chain.last == "body"
          # `ctx.body` standalone access — request body indicator.
          block.call(:body, "")
        end
      when "subscript_expression"
        target = first_named_child(node)
        if target
          base = navigation_chain(target, source)
          idx = base.index { |seg| seg == "query" || seg == "headers" || seg == "cookie" }
          if idx && idx == base.size - 1
            key = subscript_string_key(node, source)
            if key
              case base[idx]
              when "query"   then block.call(:query, key)
              when "headers" then block.call(:header, key)
              when "cookie"  then block.call(:cookie, key)
              end
            end
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler_body(child, source, &block)
      end
    end

    # ---- shape helpers ----------------------------------------------

    private def navigation_chain(node : LibTreeSitter::TSNode, source : String) : Array(String)
      chain = [] of String
      collect_chain(node, source, chain)
      chain
    end

    private def collect_chain(node : LibTreeSitter::TSNode, source : String, chain : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "identifier"
        chain << Noir::TreeSitter.node_text(node, source)
      when "member_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          ty = Noir::TreeSitter.node_type(child)
          case ty
          when "identifier", "member_expression"
            collect_chain(child, source, chain)
          when "property_identifier"
            chain << Noir::TreeSitter.node_text(child, source)
          else
            chain.clear
            chain << ""
            return
          end
        end
      else
        chain.clear
        chain << ""
      end
    end

    private def subscript_string_key(node : LibTreeSitter::TSNode, source : String) : String?
      seen_target = false
      Noir::TreeSitter.each_named_child(node) do |child|
        if !seen_target
          seen_target = true
          next
        end
        if Noir::TreeSitter.node_type(child) == "string"
          return decode_string(child, source)
        end
      end
      nil
    end

    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    private def arguments_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "arguments"
      end
      nil
    end

    # Pull the body out of an arrow function — the trailing child
    # after the parameter list. Returns nil for arrow functions
    # without a body (rare; would be parse-error territory).
    private def arrow_body(arrow : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      seen_params = false
      Noir::TreeSitter.each_named_child(arrow) do |child|
        ty = Noir::TreeSitter.node_type(child)
        if !seen_params && (ty == "formal_parameters" || ty == "identifier")
          seen_params = true
          next
        end
        return child if seen_params
      end
      nil
    end

    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      if raw.size >= 2 && (raw[0] == '\'' || raw[0] == '"' || raw[0] == '`') && raw[0] == raw[-1]
        raw[1..-2]
      else
        raw
      end
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
