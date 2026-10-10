require "../ext/tree_sitter/tree_sitter"
require "./js_object_config_extractor"
require "../utils/url_path"

module Noir
  # Tree-sitter reader for React Router v7's route config (`app/routes.ts`).
  #
  # ```
  # export default [
  #   index("routes/home.tsx"),
  #   route("about", "routes/about.tsx"),
  #   layout("routes/auth/layout.tsx", [
  #     route("login", "routes/auth/login.tsx"),
  #   ]),
  #   ...prefix("concerts", [
  #     route(":city", "routes/concerts/city.tsx"),
  #   ]),
  #   ...(await flatRoutes()),
  # ] satisfies RouteConfig;
  # ```
  #
  # Yields one `Route` per `route()` / `index()` call with the path joined
  # through every enclosing `route()` / `prefix()`, in React Router syntax
  # (`/concerts/:city`). `layout()` adds no path and is not itself a URL.
  # `flatRoutes()` is reported as a flag: the file convention it turns on
  # is the analyzer's business, not the config's.
  module TreeSitterReactRouterConfigExtractor
    extend self

    struct Route
      getter path : String
      # As written: relative to the app directory (`routes/home.tsx`).
      getter file : String
      # 1-based, for `PathInfo`.
      getter line : Int32

      def initialize(@path, @file, @line)
      end
    end

    struct Config
      getter routes : Array(Route)
      getter? flat_routes : Bool

      def initialize(@routes, @flat_routes)
      end
    end

    def extract(source : String) : Config
      # The JS grammar has neither `satisfies` nor `const x: T =`; both strips
      # are same-line, so rows hold.
      normalized = source
        .gsub(JSObjectConfigExtractor::DECLARATION_ANNOTATION, "\\1 =")
        .gsub(JSObjectConfigExtractor::SATISFIES_ASSERTION, "")
      walker = Walker.new(normalized)
      Noir::TreeSitter.parse_javascript(normalized) { |root| walker.run(root) }
      Config.new(walker.routes, walker.flat_routes?)
    end

    # Walks what the module default-exports, so an unused array or a
    # commented-out `flatRoutes()` contributes nothing. Identifiers resolve
    # to same-file `const x = ...` bindings, which is how a config is split
    # into named arrays (`...prefix("api", apiRoutes)`).
    private class Walker
      getter routes = [] of Route
      getter? flat_routes = false

      @bindings = {} of String => LibTreeSitter::TSNode
      @resolving = Set(String).new

      def initialize(@source : String)
      end

      def run(root : LibTreeSitter::TSNode) : Nil
        exported = nil
        Noir::TreeSitter.walk(root) do |node|
          case Noir::TreeSitter.node_type(node)
          when "variable_declarator"
            name = Noir::TreeSitter.field(node, "name")
            value = Noir::TreeSitter.field(node, "value")
            @bindings[text(name)] = value if name && value && Noir::TreeSitter.node_type(name) == "identifier"
          when "export_statement"
            exported ||= Noir::TreeSitter.field(node, "value")
          end
        end
        # No `export default` (CommonJS, a parse error): read the whole file.
        target = exported # a block-captured var does not narrow
        walk(target, "/") if target
        # No `export default` we could follow (CommonJS, a parse error, an
        # export built some other way): read every helper call in the file.
        walk(root, "/") if @routes.empty? && !@flat_routes
      end

      # `absorb`: `node` sits directly under a `prefix()` (layouts pass it
      # through), whose `joinRoutePaths` absorbs a child's leading `/`.
      private def walk(node : LibTreeSitter::TSNode, parent : String, absorb : Bool = false) : Nil
        case Noir::TreeSitter.node_type(node)
        when "identifier"
          name = text(node)
          if (bound = @bindings[name]?) && @resolving.add?(name)
            walk(bound, parent, absorb)
            @resolving.delete(name)
          end
          return
        when "call_expression"
          case callee_name(node)
          when "route", "index", "layout", "prefix"
            emit(node, parent, absorb)
            return
          when "flatRoutes"
            @flat_routes = true
            return
          end
        end

        Noir::TreeSitter.each_named_child(node) { |child| walk(child, parent, absorb) }
      end

      private def emit(call : LibTreeSitter::TSNode, parent : String, absorb : Bool) : Nil
        args = [] of LibTreeSitter::TSNode
        if arguments = Noir::TreeSitter.field(call, "arguments")
          Noir::TreeSitter.each_named_arg(arguments) { |arg| args << arg }
        end
        line = Noir::TreeSitter.node_start_row(call) + 1

        child_parent = parent
        child_absorb = absorb
        case callee_name(call)
        when "route"
          path, file = literal(args[0]?), literal(args[1]?)
          return unless path && file
          # Outside a prefix, an absolute child path must already spell the
          # parent out, so it stands as written.
          child_parent = path.starts_with?('/') && !absorb ? path : Noir::URLPath.join_absorbing(parent, path)
          child_absorb = false
          @routes << Route.new(child_parent, file, line)
        when "index"
          file = literal(args[0]?)
          @routes << Route.new(parent, file, line) if file
          return
        when "prefix"
          path = literal(args[0]?)
          return unless path
          child_parent = Noir::URLPath.join_absorbing(parent, path)
          child_absorb = true
        end

        # Children: the trailing array of route/layout/prefix, a binding to
        # one, or a `defineRoutes`-style callback (Remix's routes adapter).
        return unless children = args.last?
        case Noir::TreeSitter.node_type(children)
        when "array", "identifier", "arrow_function", "function_expression"
          walk(children, child_parent, child_absorb)
        end
      end

      private def callee_name(call : LibTreeSitter::TSNode) : String?
        callee = Noir::TreeSitter.field(call, "function")
        text(callee) if callee && Noir::TreeSitter.node_type(callee) == "identifier"
      end

      # A string or substitution-free template literal. Fragments only:
      # `''` has none, and its raw text is not a path.
      private def literal(node : LibTreeSitter::TSNode?) : String?
        return unless node
        type = Noir::TreeSitter.node_type(node)
        return unless type == "string" || type == "template_string"
        String.build do |io|
          Noir::TreeSitter.each_named_child(node) do |child|
            case Noir::TreeSitter.node_type(child)
            when "string_fragment"       then io << text(child)
            when "escape_sequence"       then io << Noir::TreeSitter.unescape(text(child))
            when "template_substitution" then return
            end
          end
        end
      end

      private def text(node : LibTreeSitter::TSNode) : String
        Noir::TreeSitter.node_text(node, @source)
      end
    end
  end
end
