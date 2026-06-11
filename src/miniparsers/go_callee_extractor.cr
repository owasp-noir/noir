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
#   * `selector_expression` — resolve unambiguous same-package method
#     values (`handler.Get`) through `external_methods`, and imported
#     top-level function handlers (`pkg.Foo`) when the analyzer supplies
#     a go.mod-backed import-path function index.
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
                            external_methods : Hash(String, Array(FunctionBody)) = Hash(String, Array(FunctionBody)).new,
                            imported_functions : Hash(String, Hash(String, FunctionBody)) = Hash(String, Hash(String, FunctionBody)).new,
                            imported_methods : Hash(String, Hash(String, Array(FunctionBody))) = Hash(String, Hash(String, Array(FunctionBody))).new)
    return Hash(Int32, Array(Tuple(String, String, Int32))).new unless enabled
    callees_for_routes(source, file_path, route_rows, external_functions, external_methods, imported_functions, imported_methods)
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
                         external_methods : Hash(String, Array(FunctionBody)) = Hash(String, Array(FunctionBody)).new,
                         imported_functions : Hash(String, Hash(String, FunctionBody)) = Hash(String, Hash(String, FunctionBody)).new,
                         imported_methods : Hash(String, Hash(String, Array(FunctionBody))) = Hash(String, Hash(String, Array(FunctionBody))).new)
    by_route = Hash(Int32, Array(Tuple(String, String, Int32))).new
    return by_route if route_rows.empty?
    import_aliases = imported_functions.empty? && imported_methods.empty? ? Hash(String, String).new : extract_import_aliases(source)
    imported_receiver_vars = imported_methods.empty? ? Hash(String, String).new : extract_imported_receiver_vars(source, import_aliases)

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

        callees = [] of Tuple(String, String, Int32)
        find_handler_args(node, source).each do |raw_handler_arg|
          append_callees_for_handler_arg(
            unwrap_handler_arg(raw_handler_arg, source),
            source,
            file_path,
            local_functions,
            external_functions,
            external_methods,
            import_aliases,
            imported_functions,
            imported_methods,
            imported_receiver_vars,
            callees
          )
        end

        by_route[row] = callees unless callees.empty?
      end
    end

    by_route
  end

  private def append_callees_for_handler_arg(handler_arg : LibTreeSitter::TSNode,
                                             source : String,
                                             file_path : String,
                                             local_functions : Hash(String, LibTreeSitter::TSNode),
                                             external_functions : Hash(String, FunctionBody),
                                             external_methods : Hash(String, Array(FunctionBody)),
                                             import_aliases : Hash(String, String),
                                             imported_functions : Hash(String, Hash(String, FunctionBody)),
                                             imported_methods : Hash(String, Hash(String, Array(FunctionBody))),
                                             imported_receiver_vars : Hash(String, String),
                                             sink : Array(Tuple(String, String, Int32)))
    callees = [] of Tuple(String, String, Int32)

    case Noir::TreeSitter.node_type(handler_arg)
    when "func_literal"
      if body = Noir::TreeSitter.field(handler_arg, "body")
        walk_calls_in_node(body, source, file_path, callees, 0, external_functions)
      end
    when "identifier"
      append_callees_for_identifier_handler(
        Noir::TreeSitter.node_text(handler_arg, source),
        source,
        file_path,
        local_functions,
        external_functions,
        external_methods,
        callees
      )
    when "selector_expression"
      append_callees_for_selector_handler(
        handler_arg,
        source,
        external_functions,
        external_methods,
        import_aliases,
        imported_functions,
        imported_methods,
        imported_receiver_vars,
        callees
      )
    when "call_expression"
      if function = Noir::TreeSitter.field(handler_arg, "function")
        case Noir::TreeSitter.node_type(function)
        when "identifier"
          append_callees_for_identifier_handler(
            Noir::TreeSitter.node_text(function, source),
            source,
            file_path,
            local_functions,
            external_functions,
            external_methods,
            callees
          )
        when "selector_expression"
          append_callees_for_selector_handler(
            function,
            source,
            external_functions,
            external_methods,
            import_aliases,
            imported_functions,
            imported_methods,
            imported_receiver_vars,
            callees
          )
        end
      end

      if fallback = fallback_handler_arg_from_call(handler_arg, source, local_functions, external_functions, external_methods)
        append_callees_for_handler_arg(
          unwrap_handler_arg(fallback, source),
          source,
          file_path,
          local_functions,
          external_functions,
          external_methods,
          import_aliases,
          imported_functions,
          imported_methods,
          imported_receiver_vars,
          callees
        )
      end
    else
      # other shapes (index/lambda results) — out of scope.
    end

    if callees.empty?
      if fallback = unresolved_handler_reference(handler_arg, source, file_path)
        callees << fallback
      end
    end

    callees.each { |entry| sink << entry unless sink.includes?(entry) }
  end

  private def append_callees_for_identifier_handler(name : String,
                                                    source : String,
                                                    file_path : String,
                                                    local_functions : Hash(String, LibTreeSitter::TSNode),
                                                    external_functions : Hash(String, FunctionBody),
                                                    external_methods : Hash(String, Array(FunctionBody)),
                                                    sink : Array(Tuple(String, String, Int32)))
    if fn_node = local_functions[name]?
      if body = Noir::TreeSitter.field(fn_node, "body")
        walk_calls_in_node(body, source, file_path, sink, 0, external_functions)
      end
    elsif extern = external_functions[name]?
      sink.concat(calls_in_external(extern, external_functions))
    elsif (methods = external_methods[name]?) && methods.size == 1
      # A bare identifier that resolves to a single same-package method
      # (rare, but `Handle("/x", Foo)` where `Foo` is a method value
      # lifted to package scope).
      sink.concat(calls_in_external(methods.first, external_functions))
    end
  end

  private def fallback_handler_arg_from_call(call_node : LibTreeSitter::TSNode,
                                             source : String,
                                             local_functions : Hash(String, LibTreeSitter::TSNode),
                                             external_functions : Hash(String, FunctionBody),
                                             external_methods : Hash(String, Array(FunctionBody))) : LibTreeSitter::TSNode?
    args = Noir::TreeSitter.field(call_node, "arguments")
    return unless args

    Noir::TreeSitter.each_named_child(args) do |arg|
      next if string_literal_node?(arg)
      candidate = unwrap_handler_arg(arg, source)
      return candidate if fallback_handler_candidate?(candidate, source, local_functions, external_functions, external_methods)
    end

    nil
  end

  private def fallback_handler_candidate?(node : LibTreeSitter::TSNode,
                                          source : String,
                                          local_functions : Hash(String, LibTreeSitter::TSNode),
                                          external_functions : Hash(String, FunctionBody),
                                          external_methods : Hash(String, Array(FunctionBody))) : Bool
    case Noir::TreeSitter.node_type(node)
    when "func_literal", "selector_expression", "call_expression", "variadic_argument"
      true
    when "identifier"
      name = Noir::TreeSitter.node_text(node, source)
      local_functions.has_key?(name) || external_functions.has_key?(name) || external_methods.has_key?(name)
    else
      false
    end
  end

  private def unresolved_handler_reference(handler_arg : LibTreeSitter::TSNode,
                                           source : String,
                                           file_path : String) : Tuple(String, String, Int32)?
    ref_node = case Noir::TreeSitter.node_type(handler_arg)
               when "selector_expression"
                 handler_arg
               when "call_expression"
                 Noir::TreeSitter.field(handler_arg, "function")
               end
    return unless ref_node

    name = callee_text(ref_node, source)
    return if name.empty?
    return if BUILTINS.includes?(name)
    return if name.starts_with?("_")

    {name, file_path, Noir::TreeSitter.node_start_row(ref_node) + 1}
  end

  private def append_callees_for_selector_handler(handler_arg : LibTreeSitter::TSNode,
                                                  source : String,
                                                  external_functions : Hash(String, FunctionBody),
                                                  external_methods : Hash(String, Array(FunctionBody)),
                                                  import_aliases : Hash(String, String),
                                                  imported_functions : Hash(String, Hash(String, FunctionBody)),
                                                  imported_methods : Hash(String, Hash(String, Array(FunctionBody))),
                                                  imported_receiver_vars : Hash(String, String),
                                                  sink : Array(Tuple(String, String, Int32)))
    if imported = calls_for_imported_selector(handler_arg, source, import_aliases, imported_functions)
      sink.concat(imported)
      return
    elsif imported = calls_for_imported_receiver_method(handler_arg, source, imported_receiver_vars, imported_methods, imported_functions)
      sink.concat(imported)
      return
    end

    # Method-value handler: `as.Campaigns`, `s.handleOIDCRedirect`,
    # `ctrl.Index`. Resolve by the field (method) name against the
    # package method-body map only after imported selectors have had a
    # chance to resolve; otherwise `api.Get` or an imported
    # `controller.Show` can be misattributed to a same-package method
    # with the same field name.
    field = Noir::TreeSitter.field(handler_arg, "field")
    if field
      method_name = Noir::TreeSitter.node_text(field, source)
      if (methods = external_methods[method_name]?) && methods.size == 1
        sink.concat(calls_in_external(methods.first, external_functions))
      end
    end
  end

  # Non-string positional arguments after the path in a verb-route call.
  # Mirrors the convention used by
  # `TreeSitterGoRouteExtractor#decode_verb_call`.
  #
  # Mux builder chains are the exception: `.Path("/x").HandlerFunc(h)`
  # carries the path and handler in different calls. When the routed call
  # itself is `Handler` / `HandlerFunc`, every non-string arg is treated
  # as a handler candidate.
  private def find_handler_args(call_node : LibTreeSitter::TSNode, source : String) : Array(LibTreeSitter::TSNode)
    found = [] of LibTreeSitter::TSNode
    args = Noir::TreeSitter.field(call_node, "arguments")
    return found unless args
    handler_only = handler_only_call?(call_node, source)

    if handler_only
      # `.Handler(h)` / `.HandlerFunc(h)` builder calls: the handlers are
      # all non-string arguments.
      Noir::TreeSitter.each_named_child(args) do |arg|
        ty = Noir::TreeSitter.node_type(arg)
        next if ty == "interpreted_string_literal" || ty == "raw_string_literal"
        found << arg
      end
      return found
    end

    # Verb/registration calls are path-first (`r.Get("/x", h)`). Treat the
    # FIRST positional argument as the path — a string literal in most
    # apps, but just as often a path constant/variable
    # (`r.Get(tokenPath, h)`) or a concatenation — then take the next
    # non-string arguments as handlers. Keying off "first arg = path"
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
      found << arg
    end
    found
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
  # gorilla/mux, chi, and generated Hertz apps:
  #
  #   * `http.HandlerFunc(h)`                         -> `h`
  #   * `mid.Use(as.Foo, mid.RequireLogin)`           -> `as.Foo`
  #   * `http.StripPrefix("/x", fileServer)`          -> `fileServer`
  #   * `append(_mw(), handler)...`                    -> `handler`
  #   * nested combinations (`mid.Use(http.HandlerFunc(h), ...)`)
  #
  # Only known wrapper calls are peeled. Unknown call_expression handlers
  # (for example `handlers.GetBooks(service)`) are preserved so the callee
  # resolver can walk the factory function body instead of losing it by
  # unwrapping to an arbitrary argument.
  private def unwrap_handler_arg(arg : LibTreeSitter::TSNode, source : String, depth : Int32 = 0) : LibTreeSitter::TSNode
    return arg if depth > 4

    if Noir::TreeSitter.node_type(arg) == "variadic_argument"
      return arg unless variadic_inner = first_named_child(arg)
      return unwrap_handler_arg(variadic_inner, source, depth + 1)
    end

    return arg unless Noir::TreeSitter.node_type(arg) == "call_expression"

    args = Noir::TreeSitter.field(arg, "arguments")
    return arg unless args

    function = Noir::TreeSitter.field(arg, "function")
    wrapper_name = function ? callee_text(function, source) : ""
    return arg unless handler_wrapper_call?(wrapper_name)

    inner : LibTreeSitter::TSNode? = nil
    if wrapper_name == "append"
      Noir::TreeSitter.each_named_child(args) do |child|
        next if string_literal_node?(child)
        inner = child
      end
    else
      Noir::TreeSitter.each_named_child(args) do |child|
        next if string_literal_node?(child)
        inner = child
        break
      end
    end
    return arg unless found = inner
    unwrap_handler_arg(found, source, depth + 1)
  end

  private def handler_wrapper_call?(name : String) : Bool
    return true if name == "append"
    return true if name == "HandlerFunc" || name.ends_with?(".HandlerFunc")
    return true if name == "HertzHandler" || name.ends_with?(".HertzHandler")
    return true if name == "StripPrefix" || name.ends_with?(".StripPrefix")
    return true if name == "Use" || name.ends_with?(".Use")
    false
  end

  private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    found : LibTreeSitter::TSNode? = nil
    Noir::TreeSitter.each_named_child(node) do |child|
      found = child
      break
    end
    found
  end

  private def identifier_or_first_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    return node if Noir::TreeSitter.node_type(node) == "identifier"
    first_named_child(node)
  end

  private def string_literal_node?(node : LibTreeSitter::TSNode) : Bool
    ty = Noir::TreeSitter.node_type(node)
    ty == "interpreted_string_literal" || ty == "raw_string_literal"
  end

  private def calls_for_imported_selector(handler_arg : LibTreeSitter::TSNode,
                                          source : String,
                                          import_aliases : Hash(String, String),
                                          imported_functions : Hash(String, Hash(String, FunctionBody))) : Array(Tuple(String, String, Int32))?
    return if import_aliases.empty? || imported_functions.empty?

    operand = Noir::TreeSitter.field(handler_arg, "operand")
    field = Noir::TreeSitter.field(handler_arg, "field")
    return unless operand && field
    return unless Noir::TreeSitter.node_type(operand) == "identifier"

    package_ref = Noir::TreeSitter.node_text(operand, source)
    import_path = import_aliases[package_ref]?
    return unless import_path

    package_functions = imported_functions[import_path]?
    return unless package_functions

    fn_name = Noir::TreeSitter.node_text(field, source)
    fn = package_functions[fn_name]?
    return unless fn

    calls_in_external(fn, package_functions)
  end

  private def calls_for_imported_receiver_method(handler_arg : LibTreeSitter::TSNode,
                                                 source : String,
                                                 imported_receiver_vars : Hash(String, String),
                                                 imported_methods : Hash(String, Hash(String, Array(FunctionBody))),
                                                 imported_functions : Hash(String, Hash(String, FunctionBody))) : Array(Tuple(String, String, Int32))?
    return if imported_receiver_vars.empty? || imported_methods.empty?

    operand = Noir::TreeSitter.field(handler_arg, "operand")
    field = Noir::TreeSitter.field(handler_arg, "field")
    return unless operand && field
    return unless Noir::TreeSitter.node_type(operand) == "identifier"

    receiver_name = Noir::TreeSitter.node_text(operand, source)
    import_path = imported_receiver_vars[receiver_name]?
    return unless import_path

    package_methods = imported_methods[import_path]?
    return unless package_methods

    method_name = Noir::TreeSitter.node_text(field, source)
    methods = package_methods[method_name]?
    return unless methods && methods.size == 1

    package_functions = imported_functions[import_path]? || Hash(String, FunctionBody).new
    calls_in_external(methods.first, package_functions)
  end

  private def extract_imported_receiver_vars(source : String, import_aliases : Hash(String, String)) : Hash(String, String)
    vars = Hash(String, String).new
    return vars if import_aliases.empty?

    Noir::TreeSitter.parse_go(source) do |root|
      walk(root) do |node|
        next unless imported_receiver_assignment_node?(node)

        left = Noir::TreeSitter.field(node, "left")
        right = Noir::TreeSitter.field(node, "right")
        if Noir::TreeSitter.node_type(node) == "var_spec"
          left = Noir::TreeSitter.field(node, "name")
          right = Noir::TreeSitter.field(node, "value")
        end
        next unless left && right

        var_node = identifier_or_first_child(left)
        rhs = first_named_child(right)
        next unless var_node && rhs
        next unless Noir::TreeSitter.node_type(var_node) == "identifier"

        import_path = imported_receiver_import_path(rhs, source, import_aliases)
        next unless import_path

        vars[Noir::TreeSitter.node_text(var_node, source)] ||= import_path
      end
    end

    vars
  end

  private def imported_receiver_assignment_node?(node : LibTreeSitter::TSNode) : Bool
    case Noir::TreeSitter.node_type(node)
    when "short_var_declaration", "assignment_statement", "var_spec"
      true
    else
      false
    end
  end

  private def imported_receiver_import_path(node : LibTreeSitter::TSNode,
                                            source : String,
                                            import_aliases : Hash(String, String)) : String?
    case Noir::TreeSitter.node_type(node)
    when "call_expression"
      function = Noir::TreeSitter.field(node, "function")
      return unless function
      import_path_for_selector(function, source, import_aliases)
    when "unary_expression", "parenthesized_expression"
      first_named_child(node).try { |child| imported_receiver_import_path(child, source, import_aliases) }
    when "composite_literal"
      type_node = Noir::TreeSitter.field(node, "type")
      return unless type_node
      import_path_for_selector(type_node, source, import_aliases)
    end
  end

  private def import_path_for_selector(node : LibTreeSitter::TSNode,
                                       source : String,
                                       import_aliases : Hash(String, String)) : String?
    return unless Noir::TreeSitter.node_type(node) == "selector_expression"
    operand = Noir::TreeSitter.field(node, "operand")
    return unless operand && Noir::TreeSitter.node_type(operand) == "identifier"

    import_aliases[Noir::TreeSitter.node_text(operand, source)]?
  end

  private def extract_import_aliases(source : String) : Hash(String, String)
    aliases = Hash(String, String).new
    Noir::TreeSitter.parse_go(source) do |root|
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "import_spec"

        alias_name : String? = nil
        import_path : String? = nil
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "package_identifier"
            alias_name = Noir::TreeSitter.node_text(child, source)
          when "interpreted_string_literal", "raw_string_literal"
            import_path = unquote_import_path(Noir::TreeSitter.node_text(child, source))
          end
        end

        next unless path = import_path
        name = alias_name || default_import_alias(path)
        next if name.empty? || name == "_" || name == "."
        aliases[name] = path
      end
    end
    aliases
  end

  private def unquote_import_path(text : String) : String
    return text[1...-1] if text.size >= 2 && ((text.starts_with?("\"") && text.ends_with?("\"")) || (text.starts_with?("`") && text.ends_with?("`")))
    text
  end

  private def default_import_alias(import_path : String) : String
    parts = import_path.split("/")
    return "" if parts.empty?
    last = parts.last
    if last.matches?(/^v\d+$/) && parts.size > 1
      parts[-2]
    else
      last
    end
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
