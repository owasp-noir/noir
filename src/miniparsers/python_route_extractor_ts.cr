require "../ext/tree_sitter/tree_sitter"

module Noir
  # Tree-sitter-backed port of `PythonRouteExtractor`.
  #
  # Unlike the regex extractor (which is line-oriented and relies on the
  # caller to loop over lines), this one parses the whole source once and
  # walks the resulting AST. That buys us:
  #
  #   * decorators split across multiple lines
  #   * paths / methods containing commas, brackets, or nested quotes
  #   * precise `def`/`class` line discovery without a forward-scanning heuristic
  #
  # Behaviour mirrors the regex extractor closely enough that the same
  # analyzer adapters could switch to it with minimal changes; parity is
  # verified in `spec/unit_test/miniparser/python_route_extractor_ts_spec.cr`.
  module TreeSitterPythonRouteExtractor
    extend self

    HTTP_METHODS = %w[get post put patch delete head options trace]

    # A `@<router>.route(...)` or `@<router>.<method>(...)` decorator, paired
    # with the `def`/`class` it applies to.
    struct Decoration
      getter router_name : String
      getter attribute_name : String # "route", "get", "post", ...
      getter path : String
      getter methods : Array(String)
      getter decorator_line : Int32 # 0-based line number of the decorator
      getter def_line : Int32       # 0-based line of the def/class (-1 if none found)
      getter def_name : String      # name of the def/class (empty if not found)

      def initialize(@router_name, @attribute_name, @path, @methods, @decorator_line, @def_line, @def_name)
      end
    end

    # A `name = (module.)?Blueprint(url_prefix="...")` declaration.
    struct BlueprintDecl
      getter name : String
      getter prefix : String
      getter line : Int32

      def initialize(@name, @prefix, @line)
      end
    end

    # Parses `source` and returns every route decoration found.
    #
    # `router_names` optionally restricts which variable names count as
    # routers; `nil` accepts any identifier (matching the regex extractor,
    # which doesn't gate on the name).
    def extract_decorations(source : String, router_names : Array(String)? = nil) : Array(Decoration)
      results = [] of Decoration
      Noir::TreeSitter.parse_python(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "decorated_definition"
          collect_decorations(node, source, router_names, results)
        end
      end
      results
    end

    # Parses `source` and returns every `Blueprint(...)` assignment that
    # matches one of `module_names` or a bare `Blueprint`.
    #
    # `module_names` is the list of module prefixes allowed before
    # `.Blueprint` (e.g. `["flask"]`). A bare `Blueprint` call is always
    # accepted, matching the regex extractor.
    #
    # Uses a tree-sitter query to find the two Blueprint assignment
    # shapes (bare and module-qualified). The `url_prefix` keyword is
    # still extracted procedurally because a Blueprint may be declared
    # without one and the query language can't express "this keyword,
    # if present" cleanly.
    def extract_blueprints(source : String, module_names : Array(String)) : Array(BlueprintDecl)
      results = [] of BlueprintDecl
      allowed = module_names.to_set
      query = blueprint_query
      Noir::TreeSitter.parse_python(source) do |root|
        query.each_match_raw(root, source) do |pattern_index, caps|
          captures = caps.to_h
          name_node = captures["name"]?
          call_node = captures["call"]?
          next unless name_node && call_node

          # Pattern 1 is the qualified form; enforce the module allowlist.
          if pattern_index == 1
            module_node = captures["module"]?
            next unless module_node
            next unless allowed.includes?(Noir::TreeSitter.node_text(module_node, source))
          end

          name = Noir::TreeSitter.node_text(name_node, source)
          prefix = extract_url_prefix(call_node, source)
          results << BlueprintDecl.new(name, prefix, Noir::TreeSitter.node_start_row(name_node))
        end
      end
      results
    end

    # Lazily compiled, cached across all calls. Two patterns keep bare
    # and qualified Blueprint shapes separate so the evaluator can tell
    # them apart via `pattern_index`.
    @@blueprint_query : Noir::TreeSitter::Query? = nil

    private def blueprint_query : Noir::TreeSitter::Query
      if q = @@blueprint_query
        return q
      end
      # `object: (_) @module` (not `(identifier)`) so dotted prefixes
      # like `my_pkg.flask.Blueprint(...)` still match — tree-sitter
      # represents `my_pkg.flask` as an `attribute`, not an identifier,
      # and the legacy procedural decoder accepted any node by reading
      # its full text. We keep that parity.
      q = Noir::TreeSitter::Query.new(
        LibTreeSitter.tree_sitter_python,
        <<-SCM
          ; Pattern 0: bare `name = Blueprint(...)`
          (assignment
            left: (identifier) @name
            right: (call
              function: (identifier) @func) @call
            (#eq? @func "Blueprint"))

          ; Pattern 1: qualified `name = <module>.Blueprint(...)`
          (assignment
            left: (identifier) @name
            right: (call
              function: (attribute
                object: (_) @module
                attribute: (identifier) @attr)) @call
            (#eq? @attr "Blueprint"))
          SCM
      )
      @@blueprint_query = q
      q
    end

    # Walk the `call` node's arguments and return the string value of
    # the `url_prefix` keyword if present, `""` otherwise.
    private def extract_url_prefix(call_node : LibTreeSitter::TSNode, source : String) : String
      args = Noir::TreeSitter.field(call_node, "arguments")
      return "" unless args
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "keyword_argument"
        key = Noir::TreeSitter.field(arg, "name")
        val = Noir::TreeSitter.field(arg, "value")
        next unless key && val
        next unless Noir::TreeSitter.node_text(key, source) == "url_prefix"
        if Noir::TreeSitter.node_type(val) == "string"
          return decode_string(val, source)
        end
      end
      ""
    end

    # ---- private helpers --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end

    private def collect_decorations(deco_def : LibTreeSitter::TSNode,
                                    source : String,
                                    router_names : Array(String)?,
                                    sink : Array(Decoration))
      # A decorated_definition has one or more `decorator` named children
      # followed by a `function_definition` / `class_definition` in the
      # `definition` field.
      def_node = Noir::TreeSitter.field(deco_def, "definition")
      def_line = def_node ? Noir::TreeSitter.node_start_row(def_node) : -1
      def_name = ""
      if def_node && (name_node = Noir::TreeSitter.field(def_node, "name"))
        def_name = Noir::TreeSitter.node_text(name_node, source)
      end

      Noir::TreeSitter.each_named_child(deco_def) do |child|
        next unless Noir::TreeSitter.node_type(child) == "decorator"
        call = find_call_inside_decorator(child)
        next unless call
        if deco = decode_route_call(call, source, router_names)
          router_name, attribute_name, path, methods = deco
          sink << Decoration.new(
            router_name,
            attribute_name,
            path,
            methods,
            Noir::TreeSitter.node_start_row(child),
            def_line,
            def_name,
          )
        end
      end
    end

    # A `decorator` node wraps either a plain expression (`@foo`) or a
    # call expression (`@foo.route("/x")`). We want the call.
    private def find_call_inside_decorator(decorator : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(decorator) do |child|
        case Noir::TreeSitter.node_type(child)
        when "call"
          return child
        end
      end
      nil
    end

    # Given a `call` node that represents `<router>.<method>(...)` or
    # `<router>.route(...)`, returns {router_name, path, methods} or nil.
    private def decode_route_call(call : LibTreeSitter::TSNode,
                                  source : String,
                                  router_names : Array(String)?) : Tuple(String, String, String, Array(String))?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "attribute"

      object = Noir::TreeSitter.field(function, "object")
      attribute = Noir::TreeSitter.field(function, "attribute")
      return unless object && attribute
      return unless Noir::TreeSitter.node_type(object) == "identifier"
      return unless Noir::TreeSitter.node_type(attribute) == "identifier"

      router_name = Noir::TreeSitter.node_text(object, source)
      attr_name = Noir::TreeSitter.node_text(attribute, source)

      if router_names && !router_names.includes?(router_name)
        return
      end

      method_from_attr =
        if attr_name == "route"
          nil
        elsif HTTP_METHODS.includes?(attr_name)
          attr_name.upcase
        else
          return
        end

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      path = ""
      methods = [] of String
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string"
          # First positional string is the path.
          path = decode_string(arg, source) if path.empty?
        when "keyword_argument"
          name = Noir::TreeSitter.field(arg, "name")
          value = Noir::TreeSitter.field(arg, "value")
          next unless name && value
          # Accept both `methods=` (Flask / Sanic) and the singular
          # `method=` (Bottle). decode_method_list handles a list or a
          # bare string value.
          key = Noir::TreeSitter.node_text(name, source)
          if key == "methods" || key == "method"
            methods = decode_method_list(value, source)
          end
        end
      end

      return if path.empty?

      if methods.empty?
        if fallback = method_from_attr
          methods = [fallback]
        else
          methods = ["GET"] # Flask default for generic `.route` without methods=
        end
      end
      {router_name, attr_name, path, methods}
    end

    # Decodes a `string` node's content. Python strings are parsed as
    #   (string (string_start) (string_content)+ (string_end))
    # We concatenate every `string_content` child — handles implicit
    # concatenation inside one literal (`"foo" "bar"` is a separate story
    # at the argument level, not here).
    private def decode_string(string_node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(string_node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      buf
    end

    private def decode_method_list(value : LibTreeSitter::TSNode, source : String) : Array(String)
      methods = [] of String
      case Noir::TreeSitter.node_type(value)
      when "list", "tuple", "set"
        Noir::TreeSitter.each_named_child(value) do |elem|
          if Noir::TreeSitter.node_type(elem) == "string"
            methods << decode_string(elem, source).upcase
          end
        end
      when "string"
        methods << decode_string(value, source).upcase
      end
      methods
    end
  end
end
