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
    def extract_blueprints(source : String, module_names : Array(String)) : Array(BlueprintDecl)
      results = [] of BlueprintDecl
      allowed = module_names.to_set
      Noir::TreeSitter.parse_python(source) do |root|
        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "assignment"
          if bp = decode_blueprint(node, source, allowed)
            results << bp
          end
        end
      end
      results
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
      return nil unless function
      return nil unless Noir::TreeSitter.node_type(function) == "attribute"

      object = Noir::TreeSitter.field(function, "object")
      attribute = Noir::TreeSitter.field(function, "attribute")
      return nil unless object && attribute
      return nil unless Noir::TreeSitter.node_type(object) == "identifier"
      return nil unless Noir::TreeSitter.node_type(attribute) == "identifier"

      router_name = Noir::TreeSitter.node_text(object, source)
      attr_name = Noir::TreeSitter.node_text(attribute, source)

      if router_names && !router_names.includes?(router_name)
        return nil
      end

      method_from_attr : String? = nil
      if attr_name == "route"
        method_from_attr = nil
      elsif HTTP_METHODS.includes?(attr_name)
        method_from_attr = attr_name.upcase
      else
        return nil
      end

      args = Noir::TreeSitter.field(call, "arguments")
      return nil unless args

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

      return nil if path.empty?

      methods = [method_from_attr.not_nil!] if method_from_attr && methods.empty?
      methods = ["GET"] if methods.empty? # Flask default when no methods= and generic .route
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

    private def decode_blueprint(assign : LibTreeSitter::TSNode,
                                 source : String,
                                 allowed : Set(String)) : BlueprintDecl?
      left = Noir::TreeSitter.field(assign, "left")
      right = Noir::TreeSitter.field(assign, "right")
      return nil unless left && right
      return nil unless Noir::TreeSitter.node_type(right) == "call"

      name : String? = nil
      case Noir::TreeSitter.node_type(left)
      when "identifier"
        name = Noir::TreeSitter.node_text(left, source)
      else
        return nil
      end

      function = Noir::TreeSitter.field(right, "function")
      return nil unless function

      case Noir::TreeSitter.node_type(function)
      when "identifier"
        return nil unless Noir::TreeSitter.node_text(function, source) == "Blueprint"
      when "attribute"
        object = Noir::TreeSitter.field(function, "object")
        attr = Noir::TreeSitter.field(function, "attribute")
        return nil unless object && attr
        return nil unless Noir::TreeSitter.node_text(attr, source) == "Blueprint"
        # Module can be an identifier or a dotted name; take the full text.
        mod = Noir::TreeSitter.node_text(object, source)
        return nil unless allowed.includes?(mod)
      else
        return nil
      end

      prefix = ""
      if args = Noir::TreeSitter.field(right, "arguments")
        Noir::TreeSitter.each_named_child(args) do |arg|
          next unless Noir::TreeSitter.node_type(arg) == "keyword_argument"
          key = Noir::TreeSitter.field(arg, "name")
          val = Noir::TreeSitter.field(arg, "value")
          next unless key && val
          next unless Noir::TreeSitter.node_text(key, source) == "url_prefix"
          if Noir::TreeSitter.node_type(val) == "string"
            prefix = decode_string(val, source)
          end
        end
      end

      BlueprintDecl.new(name.not_nil!, prefix, Noir::TreeSitter.node_start_row(assign))
    end
  end
end
