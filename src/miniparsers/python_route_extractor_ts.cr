require "../ext/tree_sitter/tree_sitter"
require "./extraction_result_cache"

module Noir
  # Tree-sitter-backed Python route decorator extractor. It parses the
  # whole source once and walks the resulting AST, which handles:
  #
  #   * decorators split across multiple lines
  #   * paths / methods containing commas, brackets, or nested quotes
  #   * precise `def`/`class` line discovery without a forward-scanning heuristic
  module TreeSitterPythonRouteExtractor
    extend self

    # `query` (RFC 10008) recognizes `@<var>.query("/path")` shortcut
    # decorators (Flask/Werkzeug shipped this; other decorator-based
    # frameworks fall through harmlessly if they never define it).
    HTTP_METHODS = %w[get post put patch delete head options trace query]

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

    # Process-wide memo: same CodeLocator source buffer is often fed to
    # decorations + blueprints (and to multiple framework analyzers).
    @@decoration_memo = Hash(UInt64, Array(Decoration)).new
    @@blueprint_memo = Hash(UInt64, Array(BlueprintDecl)).new
    @@memo_mutex = Mutex.new

    ExtractionResultCache.register_clearer do
      @@memo_mutex.synchronize do
        @@decoration_memo.clear
        @@blueprint_memo.clear
      end
    end

    # Parses `source` and returns every route decoration found.
    #
    # `router_names` optionally restricts which variable names count as
    # routers; `nil` accepts any identifier.
    #
    # `extra_attributes` optionally widens the set of decorator attribute
    # names that count as a route. Each entry maps an attribute name
    # (e.g. `"websocket"`) to the HTTP method the synthesised endpoint
    # should carry (Quart's `@app.websocket` is emitted as `GET` so the
    # downstream pipeline keeps treating it as an HTTP-shaped endpoint;
    # the caller flips `protocol = "ws"` based on `attribute_name`).
    def extract_decorations(source : String,
                            router_names : Array(String)? = nil,
                            extra_attributes : Hash(String, String)? = nil) : Array(Decoration)
      tag = decoration_options_tag(router_names, extra_attributes)
      key = ExtractionResultCache.key(source, "decorations", tag)
      ExtractionResultCache.fetch(@@decoration_memo, key, mutex: @@memo_mutex) do
        results = [] of Decoration
        Noir::TreeSitter.parse_python(source) do |root|
          extract_decorations_from(root, source, router_names, extra_attributes, results)
        end
        results
      end
    end

    # Same as `extract_decorations` but reuses a pre-parsed root so a
    # caller that also needs blueprints (Flask/Quart/Sanic) pays for one
    # tree-sitter parse instead of two.
    def extract_decorations_from(root : LibTreeSitter::TSNode,
                                 source : String,
                                 router_names : Array(String)? = nil,
                                 extra_attributes : Hash(String, String)? = nil,
                                 results : Array(Decoration) = [] of Decoration) : Array(Decoration)
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "decorated_definition"
        collect_decorations(node, source, router_names, extra_attributes, results)
      end
      results
    end

    # Returns every `Blueprint(...)` assignment under `root` that
    # matches one of `module_names` or a bare `Blueprint`.
    #
    # `module_names` is the list of module prefixes allowed before
    # `.Blueprint` (e.g. `["flask"]`). A bare `Blueprint` call is always
    # accepted.
    #
    # Two assignment shapes count: bare `name = Blueprint(...)` and
    # qualified `name = <module>.Blueprint(...)`. The module is read as
    # full text from any node, so dotted prefixes like
    # `my_pkg.flask.Blueprint(...)` (an `attribute`, not an identifier)
    # still match.
    def extract_blueprints_from(root : LibTreeSitter::TSNode,
                                source : String,
                                module_names : Array(String),
                                results : Array(BlueprintDecl) = [] of BlueprintDecl) : Array(BlueprintDecl)
      allowed = module_names.to_set
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "assignment"
        name_node = Noir::TreeSitter.field(node, "left")
        call_node = Noir::TreeSitter.field(node, "right")
        next unless name_node && call_node
        next unless Noir::TreeSitter.node_type(name_node) == "identifier"
        next unless Noir::TreeSitter.node_type(call_node) == "call"
        function = Noir::TreeSitter.field(call_node, "function")
        next unless function

        case Noir::TreeSitter.node_type(function)
        when "identifier"
          next unless Noir::TreeSitter.node_text(function, source) == "Blueprint"
        when "attribute"
          module_node = Noir::TreeSitter.field(function, "object")
          attr_node = Noir::TreeSitter.field(function, "attribute")
          next unless module_node && attr_node
          next unless Noir::TreeSitter.node_type(attr_node) == "identifier"
          next unless Noir::TreeSitter.node_text(attr_node, source) == "Blueprint"
          next unless allowed.includes?(Noir::TreeSitter.node_text(module_node, source))
        else
          next
        end

        name = Noir::TreeSitter.node_text(name_node, source)
        prefix = extract_url_prefix(call_node, source)
        results << BlueprintDecl.new(name, prefix, Noir::TreeSitter.node_start_row(name_node))
      end
      results
    end

    # One parse → decorations + blueprints. Preferred entry for adapters
    # that need both (Flask, Quart, Sanic); result arrays are also
    # published into the individual memos so a later solo call hits.
    def extract_decorations_and_blueprints(source : String,
                                           module_names : Array(String),
                                           router_names : Array(String)? = nil,
                                           extra_attributes : Hash(String, String)? = nil) : Tuple(Array(Decoration), Array(BlueprintDecl))
      deco_tag = decoration_options_tag(router_names, extra_attributes)
      bp_tag = module_names.join(",")
      deco_key = ExtractionResultCache.key(source, "decorations", deco_tag)
      bp_key = ExtractionResultCache.key(source, "blueprints", bp_tag)

      cached_deco = nil.as(Array(Decoration)?)
      cached_bp = nil.as(Array(BlueprintDecl)?)
      @@memo_mutex.synchronize do
        cached_deco = @@decoration_memo[deco_key]?
        cached_bp = @@blueprint_memo[bp_key]?
      end
      return {cached_deco, cached_bp} if cached_deco && cached_bp

      decorations = cached_deco || [] of Decoration
      blueprints = cached_bp || [] of BlueprintDecl
      Noir::TreeSitter.parse_python(source) do |root|
        extract_decorations_from(root, source, router_names, extra_attributes, decorations) unless cached_deco
        extract_blueprints_from(root, source, module_names, blueprints) unless cached_bp
      end

      @@memo_mutex.synchronize do
        decorations = ExtractionResultCache.store_capped(@@decoration_memo, deco_key, decorations)
        blueprints = ExtractionResultCache.store_capped(@@blueprint_memo, bp_key, blueprints)
      end

      {decorations, blueprints}
    end

    private def decoration_options_tag(router_names : Array(String)?,
                                       extra_attributes : Hash(String, String)?) : String
      routers = router_names ? router_names.join(",") : "*"
      extras = if extra_attributes && !extra_attributes.empty?
                 extra_attributes.to_a.sort_by!(&.first).map { |k, v| "#{k}=#{v}" }.join("&")
               else
                 ""
               end
      "#{routers}|#{extras}"
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

    private def collect_decorations(deco_def : LibTreeSitter::TSNode,
                                    source : String,
                                    router_names : Array(String)?,
                                    extra_attributes : Hash(String, String)?,
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
        if deco = decode_route_call(call, source, router_names, extra_attributes)
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

    # `"PUT"` / `"get"` — a bare verb token, not a route path. `*` is
    # aiohttp's any-method wildcard.
    private def bare_http_method?(text : String) : Bool
      return true if text == "*"
      HTTP_METHODS.includes?(text.downcase)
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
                                  router_names : Array(String)?,
                                  extra_attributes : Hash(String, String)? = nil) : Tuple(String, String, String, Array(String))?
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
        elsif extra_attributes && extra_attributes.has_key?(attr_name)
          extra_attributes[attr_name]
        else
          return
        end

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      path = ""
      methods = [] of String
      # Positional strings in order. The path is normally the first one, but
      # aiohttp's `RouteTableDef` spells its generic decorator
      # `@routes.route('PUT', '/profile')` — method first, path second. Taking
      # the first string blindly turned that into the route `/PUT`. Collect
      # them and pick below, so a leading bare verb is read as the method it
      # is instead of as a path.
      positional_strings = [] of String
      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "string"
          positional_strings << decode_string(arg, source)
        when "keyword_argument"
          name = Noir::TreeSitter.field(arg, "name")
          value = Noir::TreeSitter.field(arg, "value")
          next unless name && value
          key = Noir::TreeSitter.node_text(name, source)
          # `methods=` (Flask / Sanic) / `method=` (Bottle).
          # `decode_method_list` handles a list or a bare string.
          if key == "methods" || key == "method"
            methods = decode_method_list(value, source)
          elsif (key == "path" || key == "rule" || key == "uri") && path.empty? &&
                Noir::TreeSitter.node_type(value) == "string"
            # `path=`/`rule=`/`uri=` keyword forms — FastAPI's
            # `@app.get(path="/x")`, Bottle's `@app.route(path="/x")`,
            # Sanic / aiohttp variants. Only accept the keyword if no
            # positional path has been seen, so a stray `path=` kwarg
            # later in the call can't overwrite a real positional.
            path = decode_string(value, source)
          end
        end
      end

      leading_verb = nil
      if path.empty?
        # A leading bare verb is only a verb when something else can be the
        # path; `@app.route("/get")` must stay a path.
        if positional_strings.size > 1 && bare_http_method?(positional_strings[0])
          leading_verb = positional_strings[0].upcase
          path = positional_strings[1]
        else
          path = positional_strings.first? || ""
        end
      end

      return if path.empty?

      if methods.empty?
        if fallback = leading_verb || method_from_attr
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
      # Walk the string's children. A regular Python string has one
      # `string_content` child; an f-string interleaves
      # `string_content` with `interpolation` nodes. Pre-fix, the
      # interpolation children were dropped entirely, so
      # `f"/api/{VERSION}/items"` collapsed to "/api//items" (and
      # then the optimizer normalized the double-slash) — the user's
      # URL silently lost the path segment.
      #
      # Preserve interpolations as `{expr}` placeholders so:
      #   * the path-parameter extractor downstream sees them and
      #     adds the param to `params` (just like a Flask
      #     `<int:id>` or FastAPI `{id}` would)
      #   * the rendered URL keeps a faithful template of the route,
      #     not a misleading partial.
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(string_node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_content"
            io << Noir::TreeSitter.node_text(child, source)
          when "interpolation"
            # Source text of an interpolation includes the braces
            # (`{VERSION}` / `{user.id}`) — write it back verbatim
            # so the placeholder shape is preserved.
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
