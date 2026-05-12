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

  # Returns the cross-file function-body map for the given directory,
  # or an empty map. Mirrors `GoEngine#ts_function_bodies_for_directory`.
  def function_bodies_for_directory(package_bodies : Hash(String, Hash(String, FunctionBody)), dir : String) : Hash(String, FunctionBody)
    package_bodies[dir]? || Hash(String, FunctionBody).new
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

  # For each call_expression at a row in `route_rows`, find the handler
  # argument, walk its body, and return the 1-hop callees keyed by row.
  # Each entry is a tuple `{name, callee_file_path, file_line_1_based}`.
  def callees_for_routes(source : String,
                         file_path : String,
                         route_rows : Set(Int32),
                         external_functions : Hash(String, FunctionBody))
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

        handler_arg = find_handler_arg(node, source)
        next unless handler_arg

        callees = [] of Tuple(String, String, Int32)
        case Noir::TreeSitter.node_type(handler_arg)
        when "func_literal"
          if body = Noir::TreeSitter.field(handler_arg, "body")
            walk_calls_in_node(body, source, file_path, callees, 0)
          end
        when "identifier"
          name = Noir::TreeSitter.node_text(handler_arg, source)
          if fn_node = local_functions[name]?
            if body = Noir::TreeSitter.field(fn_node, "body")
              walk_calls_in_node(body, source, file_path, callees, 0)
            end
          elsif extern = external_functions[name]?
            callees.concat(calls_in_external(extern))
          end
        else
          # selector_expression / method values — out of scope for now.
        end

        by_route[row] = callees unless callees.empty?
      end
    end

    by_route
  end

  # First non-string positional argument after a string-literal arg in a
  # verb-route call. Mirrors the convention used by
  # `TreeSitterGoRouteExtractor#decode_verb_call`.
  private def find_handler_arg(call_node : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
    args = Noir::TreeSitter.field(call_node, "arguments")
    return unless args
    seen_path = false
    Noir::TreeSitter.each_named_child(args) do |arg|
      ty = Noir::TreeSitter.node_type(arg)
      if ty == "interpreted_string_literal" || ty == "raw_string_literal"
        seen_path = true
        next
      end
      return arg if seen_path
    end
    nil
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
                                 line_offset : Int32)
    walk(body_node) do |n|
      next unless Noir::TreeSitter.node_type(n) == "call_expression"
      func = Noir::TreeSitter.field(n, "function")
      next unless func
      name = callee_text(func, source)
      next if name.empty?
      next if BUILTINS.includes?(name)
      next if name.starts_with?("_")
      row = Noir::TreeSitter.node_start_row(func) + line_offset
      sink << {name, file_path, row + 1}
    end
  end

  # Re-parse a sibling-file function body for cross-file identifier
  # handler resolution. Wraps the captured `function_declaration` text
  # in a `package` line so tree-sitter Go can parse it as a complete
  # `source_file`; the wrap adds exactly one row, which we subtract via
  # `start_row - 1` to map walked rows back to the original file.
  private def calls_in_external(fn : FunctionBody) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    wrapped = "package _noir_callee_wrap\n#{fn.source}\n"
    line_offset = fn.start_row - 1
    Noir::TreeSitter.parse_go(wrapped) do |root|
      Noir::TreeSitter.each_named_child(root) do |child|
        next unless Noir::TreeSitter.node_type(child) == "function_declaration"
        if body = Noir::TreeSitter.field(child, "body")
          walk_calls_in_node(body, wrapped, fn.file_path, sink, line_offset)
          break
        end
      end
    end
    sink
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
