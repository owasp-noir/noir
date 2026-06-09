require "../ext/tree_sitter/tree_sitter"

# Tree-sitter-backed Kotlin 1-hop callee extractor. Parallels
# `Noir::JavaCalleeExtractor` for JVM analyzers — both Spring (Kotlin)
# and Ktor route through this module. Kotlin's `call_expression`
# wraps either a `simple_identifier` (bare call), a
# `navigation_expression` (`a.b.c` selector chain, optionally rooted on
# `this`/`super`), or an inner `call_expression` (the `foo(...) { }`
# trailing-lambda shape). 1-hop extraction reduces to:
#
#   1. For Spring Kotlin: find the (class_name, method_name)
#      `function_declaration` in the already-parsed root and walk its
#      `function_body`.
#   2. For Ktor: walk the verb DSL call's lambda `statements` node.
#   3. For each `call_expression`, reconstruct a textual callee:
#        * `foo()`              → `foo`
#        * `service.save(x)`    → `service.save`
#        * `this.foo()`         → `this.foo`
#        * `super.foo()`        → `super.foo`
#        * `Foo.bar()` (static) → `Foo.bar`
#        * `getFoo().bar()`     → "" (chained on a call — outer dropped
#                                 as noise, inner `getFoo` still
#                                 emitted via the recursive walk)
#
# Cross-file definition resolution (e.g. `userService.save` →
# `UserServiceImpl.save` in another file) is intentionally out of
# scope for this first cut. `Callee#path` therefore points at the
# call site, matching the honest scope on every other analyzer.
module Noir::KotlinCalleeExtractor
  extend self

  # Routing DSL verbs + scoping helpers. When `skip_routing` is on
  # (Ktor handler body), a `call_expression` whose root name is in
  # this set is treated as a NESTED ROUTE — we skip both emitting it
  # and descending into its trailing lambda so the nested route's
  # callees don't leak into the parent route's list.
  ROUTING_DSL_NAMES = Set{
    "get", "post", "put", "delete", "patch", "head", "options",
    "webSocket", "webSocketRaw", "sse",
    "route", "routing", "authenticate", "rateLimit", "install",
    "intercept", "host", "port",
  }

  # Spring Kotlin entry: find the (class_name, method_name)
  # `function_declaration` in `root` and return every 1-hop
  # `call_expression` callee inside its body as
  # `{name, file_path, file_line_1_based}`. Empty array when the
  # function can't be located or its body is missing.
  def callees_in_method(root : LibTreeSitter::TSNode,
                        source : String,
                        file_path : String,
                        class_name : String,
                        method_name : String,
                        route_line : Int32? = nil) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    return sink if class_name.empty? || method_name.empty?

    fn = find_function(root, source, class_name, method_name, route_line)
    return sink unless fn
    body = function_body_node(fn)
    return sink unless body

    walk_callees(body, source, file_path, sink, skip_routing: false)
    sink
  end

  # Ktor / http4k entry: given a handler body node, return every
  # 1-hop callee inside it. `skip_routing` controls whether Ktor's
  # routing DSL (`route { ... }`, sibling verb calls, etc.) is
  # treated as a NESTED ROUTE boundary — Ktor needs this on so a
  # nested route's callees don't leak into the parent; http4k uses
  # an entirely different routing idiom (`"/x" bind GET to h`) and
  # turns the skip off so a real handler call named `get` isn't
  # silently dropped.
  def callees_in_lambda(body : LibTreeSitter::TSNode,
                        source : String,
                        file_path : String,
                        skip_routing : Bool = true) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    walk_callees(body, source, file_path, sink, skip_routing: skip_routing)
    sink
  end

  # ---- private helpers ----------------------------------------------

  private def walk_callees(node : LibTreeSitter::TSNode,
                           source : String,
                           file_path : String,
                           sink : Array(Tuple(String, String, Int32)),
                           skip_routing : Bool)
    if Noir::TreeSitter.node_type(node) == "call_expression"
      # Detect nested routing DSL BEFORE emitting/descending — for
      # the `get("/x") { ... }` shape the outermost call_expression
      # wraps an inner call_expression carrying the verb name.
      if skip_routing
        root = call_root_name(node, source)
        return if ROUTING_DSL_NAMES.includes?(root)
      end

      name = callee_text(node, source)
      unless name.empty?
        sink << {name, file_path, Noir::TreeSitter.node_start_row(node) + 1}
      end
    elsif Noir::TreeSitter.node_type(node) == "navigation_expression"
      name = enum_entries_property_text(node, source)
      unless name.empty?
        sink << {name, file_path, Noir::TreeSitter.node_start_row(node) + 1}
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      walk_callees(child, source, file_path, sink, skip_routing)
    end
  end

  # Reconstruct the textual callee for a single `call_expression`.
  # Returns "" when the call's receiver is a chained call or other
  # non-identifier shape (mirrors the Python/Go/Java chained-call
  # noise filter).
  private def callee_text(call : LibTreeSitter::TSNode, source : String) : String
    callable = first_named_child(call)
    return "" unless callable

    case Noir::TreeSitter.node_type(callable)
    when "simple_identifier"
      Noir::TreeSitter.node_text(callable, source)
    when "navigation_expression"
      navigation_text(callable, source)
    else
      # `call_expression` (trailing-lambda outer wrapper), `string_literal`,
      # `parenthesized_expression`, etc. — not a 1-hop callable shape.
      # The inner call_expression (when present) gets visited separately
      # by `walk_callees` and emitted on its own merits.
      ""
    end
  end

  # Collapse a `navigation_expression` (`a.b.c`, `this.foo`,
  # `Foo.bar`, etc.) into the joined dotted string. Returns "" if
  # any component is a call_expression (chained) or other
  # non-identifier shape.
  private def navigation_text(node : LibTreeSitter::TSNode, source : String) : String
    parts = [] of String
    Noir::TreeSitter.each_named_child(node) do |child|
      case Noir::TreeSitter.node_type(child)
      when "simple_identifier", "type_identifier"
        parts << Noir::TreeSitter.node_text(child, source)
      when "this_expression"
        parts << "this"
      when "super_expression"
        parts << "super"
      when "navigation_expression"
        inner = navigation_text(child, source)
        return "" if inner.empty?
        parts << inner
      when "navigation_suffix"
        suf = navigation_suffix_text(child, source)
        return "" if suf.empty?
        parts << suf
      else
        return ""
      end
    end
    parts.join(".")
  end

  private def enum_entries_property_text(node : LibTreeSitter::TSNode, source : String) : String
    name = navigation_text(node, source)
    return "" if name.empty?

    parts = name.split('.')
    return "" unless parts.size == 2

    receiver = parts.first
    leaf = parts.last
    return "" unless leaf == "entries"
    return "" unless receiver.matches?(/^[A-Z][A-Za-z0-9_]*$/)

    name
  end

  private def navigation_suffix_text(suffix : LibTreeSitter::TSNode, source : String) : String
    Noir::TreeSitter.each_named_child(suffix) do |child|
      if Noir::TreeSitter.node_type(child) == "simple_identifier"
        return Noir::TreeSitter.node_text(child, source)
      end
    end
    ""
  end

  # The "root" name of a call for routing-DSL detection. Only bare
  # calls qualify — `obj.get("x")` returns "" so a method named
  # `get` on a real object isn't misclassified as nested routing.
  private def call_root_name(call : LibTreeSitter::TSNode, source : String) : String
    callable = first_named_child(call)
    return "" unless callable
    case Noir::TreeSitter.node_type(callable)
    when "simple_identifier"
      Noir::TreeSitter.node_text(callable, source)
    when "call_expression"
      # `foo(...) { ... }` — outer wraps inner with trailing lambda.
      call_root_name(callable, source)
    else
      ""
    end
  end

  private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    count = LibTreeSitter.ts_node_named_child_count(node)
    return if count == 0
    LibTreeSitter.ts_node_named_child(node, 0_u32)
  end

  # Find the (class_name, method_name) `function_declaration` node.
  # Mirrors the Java extractor's `find_method` shape; Kotlin uses
  # `class_declaration` / `object_declaration` / `interface_declaration`
  # as the class container.
  private def find_function(root : LibTreeSitter::TSNode,
                            source : String,
                            class_name : String,
                            method_name : String,
                            route_line : Int32? = nil) : LibTreeSitter::TSNode?
    result : LibTreeSitter::TSNode? = nil
    walk_class_containers(root) do |decl|
      next if result
      next unless type_identifier_text(decl, source) == class_name
      body = class_body_of(decl)
      next unless body
      Noir::TreeSitter.each_named_child(body) do |member|
        next if result
        next unless Noir::TreeSitter.node_type(member) == "function_declaration"
        next unless function_name(member, source) == method_name
        if route_line
          next if Noir::TreeSitter.node_start_row(member) + 1 < route_line
        end
        result = member
      end
    end
    result
  end

  private def walk_class_containers(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    ty = Noir::TreeSitter.node_type(node)
    if ty == "class_declaration" || ty == "object_declaration" || ty == "interface_declaration"
      block.call(node)
    end
    Noir::TreeSitter.each_named_child(node) do |child|
      walk_class_containers(child, &block)
    end
  end

  private def type_identifier_text(decl : LibTreeSitter::TSNode, source : String) : String
    Noir::TreeSitter.each_named_child(decl) do |child|
      if Noir::TreeSitter.node_type(child) == "type_identifier"
        return Noir::TreeSitter.node_text(child, source)
      end
    end
    ""
  end

  private def class_body_of(decl : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    Noir::TreeSitter.each_named_child(decl) do |child|
      return child if Noir::TreeSitter.node_type(child) == "class_body"
    end
    nil
  end

  private def function_name(func : LibTreeSitter::TSNode, source : String) : String
    Noir::TreeSitter.each_named_child(func) do |child|
      if Noir::TreeSitter.node_type(child) == "simple_identifier"
        return Noir::TreeSitter.node_text(child, source)
      end
    end
    ""
  end

  # `function_declaration`'s body is a `function_body` child holding
  # either a block (`{ ... }`) or an expression body (`= expr`).
  # Walking it from `walk_callees` works for both shapes.
  private def function_body_node(func : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    Noir::TreeSitter.each_named_child(func) do |child|
      return child if Noir::TreeSitter.node_type(child) == "function_body"
    end
    nil
  end
end
