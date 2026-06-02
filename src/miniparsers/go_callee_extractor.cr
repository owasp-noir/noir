require "../ext/tree_sitter/tree_sitter"

# Tree-sitter-backed Go 1-hop callee extractor. Parallels
# `Noir::PythonCalleeExtractor` but works at the AST level — Go can't
# share the Python convention of "give me a body string", because
# tree-sitter Go needs a complete `source_file` and a bare function body
# isn't one.
#
# The extractor receives a full Go file plus the set of route call
# expression rows the analyzer cares about. For each match it locates
# the handler argument and walks the appropriate body:
#
#   * `func_literal` (inline closure handler) — walk the closure's body
#     in place; `path`/`line` on emitted callees point at the original
#     file.
#   * `identifier` (named handler) — look the name up in the file's
#     top-level `function_declaration`s first, then in
#     `external_functions` (sibling files in the same Go package). The
#     external map is built once per directory by
#     `GoEngine#collect_package_function_bodies` so cross-file lookups
#     are cheap.
#   * `selector_expression` / other shapes — skipped for the first cut.
#     Real-world examples include `pkg.Foo` (cross-package) and bound
#     method values (`handler.Get`); resolving those needs full import
#     resolution and is left as a follow-up.
#
# Builtins (`len`, `make`, `append`, …) and Go's primitive type
# constructors (`int`, `string`, `byte`, …) are filtered to keep the
# per-endpoint list focused on signal that's actually useful to an AI
# reviewer.
module Noir::GoCalleeExtractor
  extend self

  # Top-level function definition captured for cross-file identifier
  # handler resolution. `source` is the full text of the
  # `function_declaration` node, so re-parsing it yields the same body.
  # `start_row` is the 0-based row of the `func` keyword in `file_path`,
  # used to translate tree-sitter rows back to absolute file lines when
  # the body is walked from a re-parse.
  struct FunctionBody
    getter source : String
    getter file_path : String
    getter start_row : Int32

    def initialize(@source, @file_path, @start_row)
    end
  end

  # Go builtins and primitive type-conversions that carry no useful
  # signal. Anything framework-specific (`c.JSON`, `c.Query`,
  # `gin.H{...}`, etc.) is kept on purpose — those tell a reviewer how
  # the endpoint shapes input/output.
  BUILTINS = Set{
    "len", "cap", "make", "new", "append", "copy", "delete",
    "close", "panic", "recover", "print", "println",
    "string", "int", "int8", "int16", "int32", "int64",
    "uint", "uint8", "uint16", "uint32", "uint64", "uintptr", "byte", "rune",
    "float32", "float64", "complex64", "complex128", "complex",
    "bool", "error",
  }

  # Walk every cached `.go` source in `file_contents` and collect
  # top-level `function_declaration` nodes into a per-directory map
  # so cross-file identifier-handler resolution is O(1) at lookup
  # time. Keyed by directory because Go's name resolution is scoped
  # to a single package (== single directory). Module-level twin of
  # `GoEngine#collect_package_function_bodies` for analyzers (Chi)
  # that don't inherit from `GoEngine`.
  def package_function_bodies(file_contents : Hash(String, String)) : Hash(String, Hash(String, FunctionBody))
    bodies = Hash(String, Hash(String, FunctionBody)).new
    file_contents.each do |path, content|
      dir = File.dirname(path)
      fns = collect_function_bodies(content, path)
      next if fns.empty?
      bodies[dir] ||= Hash(String, FunctionBody).new
      fns.each { |name, fb| bodies[dir][name] ||= fb }
    end
    bodies
  end

  # Like `package_function_bodies`, but returns an empty map immediately
  # when `enabled` is false. Module-level twin of the
  # `GoEngine#collect_package_function_bodies` gate for analyzers that
  # don't inherit from `GoEngine`.
  def package_function_bodies_if(enabled : Bool, file_contents : Hash(String, String)) : Hash(String, Hash(String, FunctionBody))
    return Hash(String, Hash(String, FunctionBody)).new unless enabled
    package_function_bodies(file_contents)
  end

  # Returns the cross-file function-body map for the given directory,
  # or an empty map. Mirrors `GoEngine#ts_function_bodies_for_directory`.
  def function_bodies_for_directory(package_bodies : Hash(String, Hash(String, FunctionBody)), dir : String) : Hash(String, FunctionBody)
    package_bodies[dir]? || Hash(String, FunctionBody).new
  end

  # Per-directory `{method_name => [FunctionBody, ...]}` map so a
  # method-value handler (`as.Campaigns`, `ctrl.Index`) can be resolved
  # to its method body for callee extraction. Module-level twin of
  # `GoEngine#collect_package_controller_method_bodies` for analyzers
  # (Chi) that don't inherit from `GoEngine`. Returns an empty map
  # immediately when `enabled` is false so default scans pay nothing.
  def package_method_bodies_if(enabled : Bool, file_contents : Hash(String, String)) : Hash(String, Hash(String, Array(FunctionBody)))
    bodies = Hash(String, Hash(String, Array(FunctionBody))).new
    return bodies unless enabled
    file_contents.each do |path, content|
      next unless content.includes?("func (")
      methods = collect_method_bodies(content, path)
      next if methods.empty?
      dir = File.dirname(path)
      dir_map = (bodies[dir] ||= Hash(String, Array(FunctionBody)).new)
      methods.each do |name, list|
        (dir_map[name] ||= [] of FunctionBody).concat(list)
      end
    end
    bodies
  end

  # Returns the per-directory method-body map, or an empty map.
  def method_bodies_for_directory(package_method_bodies : Hash(String, Hash(String, Array(FunctionBody))), dir : String) : Hash(String, Array(FunctionBody))
    package_method_bodies[dir]? || Hash(String, Array(FunctionBody)).new
  end

  # Returns top-level function declarations in `source`, keyed by name.
  # `file_path` is recorded on each `FunctionBody` so callees emitted by
  # later re-parsing can report a useful path.
  def collect_function_bodies(source : String, file_path : String) : Hash(String, FunctionBody)
    bodies = Hash(String, FunctionBody).new
    Noir::TreeSitter.parse_go(source) do |root|
      Noir::TreeSitter.each_named_child(root) do |child|
        next unless Noir::TreeSitter.node_type(child) == "function_declaration"
        name_node = Noir::TreeSitter.field(child, "name")
        next unless name_node
        name = Noir::TreeSitter.node_text(name_node, source)
        bodies[name] ||= FunctionBody.new(
          Noir::TreeSitter.node_text(child, source),
          file_path,
          Noir::TreeSitter.node_start_row(child),
        )
      end
    end
    bodies
  end

  # Like `callees_for_routes`, but returns an empty map immediately when
  # `enabled` is false. Lets analyzers skip the tree-sitter walk on
  # default scans where callees won't be observed.
  def callees_for_routes_if(enabled : Bool,
                            source : String,
                            file_path : String,
                            route_rows : Set(Int32),
                            external_functions : Hash(String, FunctionBody),
                            external_methods : Hash(String, Array(FunctionBody)) = Hash(String, Array(FunctionBody)).new)
    return Hash(Int32, Array(Tuple(String, String, Int32))).new unless enabled
    callees_for_routes(source, file_path, route_rows, external_functions, external_methods)
  end

  # For each call_expression at a row in `route_rows`, find the handler
  # argument, walk its body, and return the 1-hop callees keyed by row.
  # Each entry is a tuple `{name, callee_file_path, file_line_1_based}`.
  #
  # `external_methods` maps a (package-unqualified) method name to the
  # bodies that define it, so a method-value handler (`as.Campaigns`,
  # `s.handleOIDCRedirect` — the dominant shape in gorilla/mux and chi
  # apps) resolves to its method body when the name is unambiguous.
  def callees_for_routes(source : String,
                         file_path : String,
                         route_rows : Set(Int32),
                         external_functions : Hash(String, FunctionBody),
                         external_methods : Hash(String, Array(FunctionBody)) = Hash(String, Array(FunctionBody)).new)
    by_route = Hash(Int32, Array(Tuple(String, String, Int32))).new
    return by_route if route_rows.empty?

    Noir::TreeSitter.parse_go(source) do |root|
      local_functions = Hash(String, LibTreeSitter::TSNode).new
      Noir::TreeSitter.each_named_child(root) do |child|
        next unless Noir::TreeSitter.node_type(child) == "function_declaration"
        name_node = Noir::TreeSitter.field(child, "name")
        next unless name_node
        local_functions[Noir::TreeSitter.node_text(name_node, source)] = child
      end

      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        row = Noir::TreeSitter.node_start_row(node)
        next unless route_rows.includes?(row)

        handler_arg = find_handler_arg(node, source).try { |arg| unwrap_handler_arg(arg, source) }
        next unless handler_arg

        callees = [] of Tuple(String, String, Int32)
        case Noir::TreeSitter.node_type(handler_arg)
        when "func_literal"
          if body = Noir::TreeSitter.field(handler_arg, "body")
            walk_calls_in_node(body, source, file_path, callees, 0, external_functions)
          end
        when "identifier"
          name = Noir::TreeSitter.node_text(handler_arg, source)
          if fn_node = local_functions[name]?
            if body = Noir::TreeSitter.field(fn_node, "body")
              walk_calls_in_node(body, source, file_path, callees, 0, external_functions)
            end
          elsif extern = external_functions[name]?
            callees.concat(calls_in_external(extern, external_functions))
          elsif (methods = external_methods[name]?) && methods.size == 1
            # A bare identifier that resolves to a single same-package
            # method (rare, but `Handle("/x", Foo)` where `Foo` is a
            # method value lifted to package scope).
            callees.concat(calls_in_external(methods.first, external_functions))
          end
        when "selector_expression"
          # Method-value handler: `as.Campaigns`, `s.handleOIDCRedirect`,
          # `ctrl.Index`. Resolve by the field (method) name against the
          # package method-body map; only attribute when the name is
          # unambiguous so a shared method name across two receiver types
          # can't mis-attribute callees.
          field = Noir::TreeSitter.field(handler_arg, "field")
          if field
            method_name = Noir::TreeSitter.node_text(field, source)
            if (methods = external_methods[method_name]?) && methods.size == 1
              callees.concat(calls_in_external(methods.first, external_functions))
            end
          end
        else
          # other shapes (index/lambda results) — out of scope.
        end

        by_route[row] = callees unless callees.empty?
      end
    end

    by_route
  end

  # First non-string positional argument after a string-literal arg in a
  # verb-route call. Mirrors the convention used by
  # `TreeSitterGoRouteExtractor#decode_verb_call`.
  #
  # Mux builder chains are the exception: `.Path("/x").HandlerFunc(h)`
  # carries the path and handler in different calls. When the routed call
  # itself is `Handler` / `HandlerFunc`, the first non-string arg is the
  # handler.
  private def find_handler_arg(call_node : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
    args = Noir::TreeSitter.field(call_node, "arguments")
    return unless args
    handler_only = handler_only_call?(call_node, source)

    if handler_only
      # `.Handler(h)` / `.HandlerFunc(h)` builder calls: the handler is
      # the first non-string argument.
      Noir::TreeSitter.each_named_child(args) do |arg|
        ty = Noir::TreeSitter.node_type(arg)
        next if ty == "interpreted_string_literal" || ty == "raw_string_literal"
        return arg
      end
      return
    end

    # Verb/registration calls are path-first (`r.Get("/x", h)`). Treat the
    # FIRST positional argument as the path — a string literal in most
    # apps, but just as often a path constant/variable
    # (`r.Get(tokenPath, h)`) or a concatenation — then take the next
    # non-string argument as the handler. Keying off "first arg = path"
    # rather than "first string literal = path" is what lets callee
    # resolution survive constant route paths.
    first = true
    Noir::TreeSitter.each_named_child(args) do |arg|
      if first
        first = false
        next
      end
      ty = Noir::TreeSitter.node_type(arg)
      next if ty == "interpreted_string_literal" || ty == "raw_string_literal"
      return arg
    end
    nil
  end

  private def handler_only_call?(call_node : LibTreeSitter::TSNode, source : String) : Bool
    function = Noir::TreeSitter.field(call_node, "function")
    return false unless function
    return false unless Noir::TreeSitter.node_type(function) == "selector_expression"
    field = Noir::TreeSitter.field(function, "field")
    return false unless field

    case Noir::TreeSitter.node_text(field, source)
    when "Handler", "HandlerFunc"
      true
    else
      false
    end
  end

  # Peel handler-wrapping calls down to the underlying handler so callee
  # resolution sees the real function. Covers the common wrappers in
  # gorilla/mux and chi apps:
  #
  #   * `http.HandlerFunc(h)`                         -> `h`
  #   * `mid.Use(as.Foo, mid.RequireLogin)`           -> `as.Foo`
  #   * `http.StripPrefix("/x", fileServer)`          -> `fileServer`
  #   * nested combinations (`mid.Use(http.HandlerFunc(h), ...)`)
  #
  # The rule is: a call_expression handler unwraps to its first non-string
  # argument (the handler position; string args are prefixes/keys). The
  # walk is depth-capped so a pathological chain can't recurse forever.
  private def unwrap_handler_arg(arg : LibTreeSitter::TSNode, source : String, depth : Int32 = 0) : LibTreeSitter::TSNode
    return arg if depth > 4
    return arg unless Noir::TreeSitter.node_type(arg) == "call_expression"

    args = Noir::TreeSitter.field(arg, "arguments")
    return arg unless args

    inner : LibTreeSitter::TSNode? = nil
    Noir::TreeSitter.each_named_child(args) do |child|
      ty = Noir::TreeSitter.node_type(child)
      next if ty == "interpreted_string_literal" || ty == "raw_string_literal"
      inner = child
      break
    end
    return arg unless found = inner
    unwrap_handler_arg(found, source, depth + 1)
  end

  # Walk `body_node` for call expressions and append `(name, file_path,
  # file_line)` tuples. `line_offset` lets callers translate
  # tree-sitter rows (already absolute when the parse covers the whole
  # file; offset by FunctionBody#start_row - 1 for re-parsed external
  # bodies wrapped with a `package` line).
  private def walk_calls_in_node(body_node : LibTreeSitter::TSNode,
                                 source : String,
                                 file_path : String,
                                 sink : Array(Tuple(String, String, Int32)),
                                 line_offset : Int32,
                                 external_functions : Hash(String, FunctionBody))
    walk(body_node) do |n|
      next unless Noir::TreeSitter.node_type(n) == "call_expression"
      func = Noir::TreeSitter.field(n, "function")
      next unless func
      name = callee_text(func, source)
      next if name.empty?
      next if BUILTINS.includes?(name)
      next if name.starts_with?("_")
      # Same-package bare identifier callees are rewritten to point at the
      # function definition; selector/method calls stay at the call-site.
      if Noir::TreeSitter.node_type(func) == "identifier" && (extern = external_functions[name]?)
        sink << {name, extern.file_path, extern.start_row + 1}
      else
        row = Noir::TreeSitter.node_start_row(func) + line_offset
        sink << {name, file_path, row + 1}
      end
    end
  end

  # Re-parse a sibling-file function/method body for cross-file handler
  # resolution. Wraps the captured declaration text in a `package` line so
  # tree-sitter Go can parse it as a complete `source_file`; the wrap adds
  # exactly one row, which we subtract via `start_row - 1` to map walked
  # rows back to the original file. Handles both `function_declaration`
  # (bare-identifier handlers) and `method_declaration` (controller-method
  # handlers, e.g. Beego's `web.Router("/x", &Ctrl{}, "get:Method")`).
  private def calls_in_external(fn : FunctionBody,
                                external_functions : Hash(String, FunctionBody)) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    wrapped = "package _noir_callee_wrap\n#{fn.source}\n"
    line_offset = fn.start_row - 1
    Noir::TreeSitter.parse_go(wrapped) do |root|
      Noir::TreeSitter.each_named_child(root) do |child|
        ty = Noir::TreeSitter.node_type(child)
        next unless ty == "function_declaration" || ty == "method_declaration"
        if body = Noir::TreeSitter.field(child, "body")
          walk_calls_in_node(body, wrapped, fn.file_path, sink, line_offset, external_functions)
          break
        end
      end
    end
    sink
  end

  # Public entry for walking a captured function/method body and
  # returning its 1-hop callees. Used by analyzers (Beego controller
  # routing) that resolve a handler to a `FunctionBody` outside the
  # standard route-row flow.
  def callees_in_body(fn : FunctionBody,
                      external_functions : Hash(String, FunctionBody) = Hash(String, FunctionBody).new) : Array(Tuple(String, String, Int32))
    calls_in_external(fn, external_functions)
  end

  # Collects top-level `method_declaration` bodies keyed by method name.
  # The value is a list because a name can be defined on several receiver
  # types in one package; callers that need an unambiguous resolution
  # should require `size == 1`. Used to attach callees to controller-style
  # routes whose handler is referenced by method name only.
  def collect_method_bodies(source : String, file_path : String) : Hash(String, Array(FunctionBody))
    bodies = Hash(String, Array(FunctionBody)).new
    Noir::TreeSitter.parse_go(source) do |root|
      Noir::TreeSitter.each_named_child(root) do |child|
        next unless Noir::TreeSitter.node_type(child) == "method_declaration"
        name_node = Noir::TreeSitter.field(child, "name")
        next unless name_node
        name = Noir::TreeSitter.node_text(name_node, source)
        (bodies[name] ||= [] of FunctionBody) << FunctionBody.new(
          Noir::TreeSitter.node_text(child, source),
          file_path,
          Noir::TreeSitter.node_start_row(child),
        )
      end
    end
    bodies
  end

  # Render a callee's textual name. Identifiers come back verbatim;
  # `selector_expression` chains rebuild into dotted names, but only
  # when every link is an identifier — chains rooted on another call
  # (`foo(x).Bar`) are dropped to keep the list signal-rich. This
  # mirrors the chained-call-noise filter in PythonCalleeExtractor.
  private def callee_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier"
      Noir::TreeSitter.node_text(node, source)
    when "selector_expression"
      operand = Noir::TreeSitter.field(node, "operand")
      field = Noir::TreeSitter.field(node, "field")
      return "" unless operand && field
      case Noir::TreeSitter.node_type(operand)
      when "identifier"
        "#{Noir::TreeSitter.node_text(operand, source)}.#{Noir::TreeSitter.node_text(field, source)}"
      when "selector_expression"
        inner = callee_text(operand, source)
        inner.empty? ? "" : "#{inner}.#{Noir::TreeSitter.node_text(field, source)}"
      else
        # operand is a call/index/literal — chained on a result, skip.
        ""
      end
    else
      ""
    end
  end

  private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    block.call(node)
    Noir::TreeSitter.each_named_child(node) do |child|
      walk(child, &block)
    end
  end
end
