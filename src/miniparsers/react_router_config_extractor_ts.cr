require "../ext/tree_sitter/tree_sitter"
require "./js_object_config_extractor"

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
      routes = [] of Route
      flat = false
      # The JS grammar has no `satisfies`; the strip is same-line, so rows hold.
      normalized = source.gsub(JSObjectConfigExtractor::SATISFIES_ASSERTION, "")
      Noir::TreeSitter.parse_javascript(normalized) do |root|
        walk(root, normalized, "/", routes) { flat = true }
      end
      Config.new(routes, flat)
    end

    private def walk(node : LibTreeSitter::TSNode, source : String, parent : String, routes : Array(Route), &on_flat : ->) : Nil
      if Noir::TreeSitter.node_type(node) == "call_expression"
        case callee_name(node, source)
        when "route", "index", "layout", "prefix"
          emit(node, source, parent, routes, &on_flat)
          return
        when "flatRoutes"
          on_flat.call
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, parent, routes, &on_flat)
      end
    end

    private def emit(call : LibTreeSitter::TSNode, source : String, parent : String, routes : Array(Route), &on_flat : ->) : Nil
      name = callee_name(call, source)
      args = [] of LibTreeSitter::TSNode
      if arguments = Noir::TreeSitter.field(call, "arguments")
        Noir::TreeSitter.each_named_child(arguments) { |arg| args << arg }
      end
      line = Noir::TreeSitter.node_start_row(call) + 1

      child_parent = parent
      case name
      when "route"
        path, file = string_arg(args, 0, source), string_arg(args, 1, source)
        return unless path && file
        child_parent = join(parent, path)
        routes << Route.new(child_parent, file, line)
      when "index"
        file = string_arg(args, 0, source)
        return unless file
        routes << Route.new(parent, file, line)
        return
      when "prefix"
        path = string_arg(args, 0, source)
        return unless path
        child_parent = join(parent, path)
      end

      # Children are the trailing array argument of route/layout/prefix.
      if (children = args.last?) && Noir::TreeSitter.node_type(children) == "array"
        walk(children, source, child_parent, routes, &on_flat)
      end
    end

    private def callee_name(call : LibTreeSitter::TSNode, source : String) : String?
      callee = Noir::TreeSitter.field(call, "function")
      return unless callee && Noir::TreeSitter.node_type(callee) == "identifier"
      Noir::TreeSitter.node_text(callee, source)
    end

    private def string_arg(args : Array(LibTreeSitter::TSNode), index : Int32, source : String) : String?
      arg = args[index]?
      return unless arg && Noir::TreeSitter.node_type(arg) == "string"
      # Fragments only: `''` has none, and its raw text is not a path.
      String.build do |io|
        Noir::TreeSitter.each_named_child(arg) do |child|
          io << Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "string_fragment"
        end
      end
    end

    # React Router resolves child paths against the parent; an absolute child
    # path must already carry the parent's, so it stands as written.
    private def join(parent : String, path : String) : String
      return parent if path.empty?
      return path if path.starts_with?("/")
      parent == "/" ? "/#{path}" : "#{parent}/#{path}"
    end
  end
end
