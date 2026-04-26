require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed walker for JVM "lambda DSL" routing styles —
  # `verb("/path", lambda)` plus optional `path("/prefix", () -> {
  # ... })` nesting. Same shape powers Javalin (`app.get("/x", ctx
  # -> ...)`), Spark Java (`get("/x", (req, res) -> ...)`), and
  # other Sinatra-flavoured Java frameworks.
  #
  # The walker is configured per framework:
  #
  #   * `verb_methods`   — method names mapped to HTTP verbs.
  #   * `nest_methods`   — method names that introduce a path
  #                        prefix (typically `path` and any
  #                        equivalent grouping helper).
  #   * `transparent_methods` — method names whose lambda body
  #                             contributes routes without changing
  #                             the prefix (Javalin's `routes`).
  #   * `query_methods` / `form_methods` / `header_methods` /
  #     `cookie_methods` — lambda-body method calls that yield an
  #     input parameter. Each takes the param name from a string
  #     argument or, when absent, falls back to surfacing the call's
  #     receiver name. Method names alone identify a category — we
  #     don't enforce a specific receiver, so framework-overlap
  #     mistakes show up as cross-framework noise rather than as
  #     missed signals.
  #   * `body_methods`   — calls that signal a request body without
  #                        a type clue (Spark's `req.body()`).
  #   * `body_typed_methods` — calls that take a class-literal
  #                            argument indicating the body type
  #                            (Javalin's `ctx.bodyAsClass(Foo.class)`).
  #
  # Out of scope for this first cut: filter chains, reverse routing,
  # cross-file route registration. Routes scoped under static factory
  # methods are still discovered as long as their lambda body lives
  # in the same file.
  module TreeSitterJvmLambdaDslExtractor
    extend self

    struct Config
      getter verb_methods : Hash(String, String)
      getter nest_methods : Set(String)
      getter transparent_methods : Set(String)
      getter query_methods : Set(String)
      getter form_methods : Set(String)
      getter header_methods : Set(String)
      getter cookie_methods : Set(String)
      getter body_methods : Set(String)
      getter body_typed_methods : Set(String)

      def initialize(@verb_methods,
                     @nest_methods,
                     @transparent_methods = Set(String).new,
                     @query_methods = Set(String).new,
                     @form_methods = Set(String).new,
                     @header_methods = Set(String).new,
                     @cookie_methods = Set(String).new,
                     @body_methods = Set(String).new,
                     @body_typed_methods = Set(String).new)
      end
    end

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32
      getter body_type : String?
      getter? has_body : Bool
      getter query_params : Array(String)
      getter form_params : Array(String)
      getter header_params : Array(String)
      getter cookie_params : Array(String)

      def initialize(@verb, @path, @line, @body_type, @has_body,
                     @query_params, @form_params, @header_params, @cookie_params)
      end
    end

    def extract_routes(source : String, config : Config) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_java(source) do |root|
        walk(root, source, "", config, routes, 0)
      end
      routes
    end

    # ---- traversal ---------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, prefix : String, config : Config, routes : Array(Route), depth : Int32)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "method_invocation"
        name = method_invocation_method_name(node, source)
        case
        when verb = config.verb_methods[name]?
          emit_route(node, source, verb, prefix, config, routes)
          return
        when config.nest_methods.includes?(name)
          path_arg = first_string_argument(node, source)
          new_prefix = path_arg ? join_paths(prefix, path_arg) : prefix
          if body = lambda_body_in_args(node)
            walk(body, source, new_prefix, config, routes, depth + 1)
          end
          return
        when config.transparent_methods.includes?(name)
          if body = lambda_body_in_args(node)
            walk(body, source, prefix, config, routes, depth + 1)
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, prefix, config, routes, depth + 1)
      end
    end

    private def emit_route(call : LibTreeSitter::TSNode,
                           source : String,
                           verb : String,
                           prefix : String,
                           config : Config,
                           routes : Array(Route))
      path_arg = first_string_argument(call, source)
      return unless path_arg

      full_path = join_paths(prefix, path_arg)
      line = Noir::TreeSitter.node_start_row(call)

      query_params = [] of String
      form_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      body_type : String? = nil
      has_body = false

      if body = lambda_body_in_args(call)
        scan_handler(body, source, config, 0) do |kind, value|
          case kind
          when :query  then query_params << value
          when :form   then form_params << value
          when :header then header_params << value
          when :cookie then cookie_params << value
          when :body   then has_body = true
          when :body_typed
            body_type = value
            has_body = true
          end
        end
      end

      routes << Route.new(verb, full_path, line, body_type, has_body,
        query_params, form_params, header_params, cookie_params)
    end

    private def scan_handler(node : LibTreeSitter::TSNode, source : String, config : Config, depth : Int32, &block : Symbol, String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      ty = Noir::TreeSitter.node_type(node)

      if ty == "method_invocation"
        name = method_invocation_method_name(node, source)

        # Don't recurse into nested verb calls — those are sibling
        # routes in their own right and the outer `walk` will reach
        # them.
        return if config.verb_methods.has_key?(name)
        return if config.nest_methods.includes?(name)

        case
        when config.query_methods.includes?(name)
          if value = first_string_argument(node, source)
            block.call(:query, value)
          end
        when config.form_methods.includes?(name)
          if value = first_string_argument(node, source)
            block.call(:form, value)
          end
        when config.header_methods.includes?(name)
          if value = first_string_argument(node, source)
            block.call(:header, value)
          end
        when config.cookie_methods.includes?(name)
          if value = first_string_argument(node, source)
            block.call(:cookie, value)
          end
        when config.body_typed_methods.includes?(name)
          type = first_class_literal_type(node, source)
          block.call(:body_typed, type || "")
        when config.body_methods.includes?(name)
          block.call(:body, "")
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler(child, source, config, depth + 1, &block)
      end
    end

    # ---- shape helpers ----------------------------------------------

    # `app.get("/x", ...)` and `Spark.get("/x", ...)` both produce
    # a `method_invocation` whose last `identifier` child before the
    # `argument_list` is the method name. Static unqualified calls
    # (`get("/x", ...)` after a static import) only have a single
    # `identifier` child preceding the `argument_list`.
    private def method_invocation_method_name(call : LibTreeSitter::TSNode, source : String) : String
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

    private def first_string_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        if Noir::TreeSitter.node_type(arg) == "string_literal"
          return decode_string_literal(arg, source)
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

    private def argument_list_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "argument_list"
      end
      nil
    end

    # Pull the lambda's body (`block` or expression) out of the
    # call's argument list. Returns nil if no lambda is passed.
    private def lambda_body_in_args(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      args = argument_list_node(call)
      return unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "lambda_expression"
        Noir::TreeSitter.each_named_child(arg) do |child|
          ty = Noir::TreeSitter.node_type(child)
          # The lambda parameter list (identifier / formal_parameters /
          # inferred_parameters) precedes the body — skip it.
          next if ty == "identifier" || ty == "formal_parameters" || ty == "inferred_parameters"
          return child
        end
      end
      nil
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

    # Single-`/` join: `prefix + suffix` with one separator,
    # collapsing trailing/leading slashes. Empty prefix or suffix is
    # passed through unchanged.
    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
