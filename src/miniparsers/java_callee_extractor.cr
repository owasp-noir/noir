require "../ext/tree_sitter/tree_sitter"

# Tree-sitter-backed Java 1-hop callee extractor. Parallels
# `Noir::PythonCalleeExtractor` / `Noir::GoCalleeExtractor` for JVM
# analyzers (Spring + framework-adapter siblings). Java's
# `method_invocation` node carries the receiver in an `object` field
# and the method name in a `name` field, so 1-hop extraction reduces
# to:
#
#   1. Find the (class_name, method_name) `method_declaration` in the
#      already-parsed root.
#   2. Walk its body for `method_invocation` nodes.
#   3. For each, reconstruct a textual callee:
#        * `foo()`              → `foo`
#        * `service.save(x)`    → `service.save`
#        * `this.foo()`         → `this.foo`
#        * `Foo.bar()` (static) → `Foo.bar`
#        * `getFoo().bar()`     → "" (chained on a call — dropped as
#                                 noise, mirroring the Python/Go
#                                 chained-call filter)
#
# Cross-file definition resolution (e.g. `userService.save` →
# `UserServiceImpl.save` in another file) is intentionally out of
# scope for this first cut. `Callee#path` therefore points at the
# call site, matching the honest scope on every other analyzer.
module Noir::JavaCalleeExtractor
  extend self

  # Java keywords that show up as receivers but carry no useful
  # callee signal on their own when stripped of the method name.
  # Currently empty — `this`/`super` *do* surface (as
  # `this.foo`/`super.foo`) and that's a useful prior; the receiver
  # walker handles them explicitly.

  # Find the matching method_declaration in `root` and return every
  # 1-hop method_invocation callee inside its body as
  # `{name, file_path, file_line_1_based}`. Empty array when the
  # method can't be located or its body is missing.
  def callees_in_method(root : LibTreeSitter::TSNode,
                        source : String,
                        file_path : String,
                        class_name : String,
                        method_name : String) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    return sink if class_name.empty? || method_name.empty?

    method_node = find_method(root, source, class_name, method_name)
    return sink unless method_node
    body = Noir::TreeSitter.field(method_node, "body")
    return sink unless body

    walk(body) do |n|
      next unless Noir::TreeSitter.node_type(n) == "method_invocation"
      name = callee_text(n, source)
      next if name.empty?
      row = Noir::TreeSitter.node_start_row(n)
      sink << {name, file_path, row + 1}
    end
    sink
  end

  # Lambda/handler entry point used by DSL analyzers (Javalin, Spark,
  # …) where the handler body is a `lambda_expression`'s body — a
  # `block` or a single expression — not a `method_declaration`.
  # Caller is responsible for locating the body (the JVM lambda DSL
  # extractor already does this for parameter scanning) and passing
  # it in. Walks the body and returns every 1-hop `method_invocation`
  # callee.
  def callees_in_lambda(body : LibTreeSitter::TSNode,
                        source : String,
                        file_path : String) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    walk(body) do |n|
      next unless Noir::TreeSitter.node_type(n) == "method_invocation"
      name = callee_text(n, source)
      next if name.empty?
      row = Noir::TreeSitter.node_start_row(n)
      sink << {name, file_path, row + 1}
    end
    sink
  end

  # ---- private helpers -----------------------------------------------

  private def callee_text(call : LibTreeSitter::TSNode, source : String) : String
    name_node = Noir::TreeSitter.field(call, "name")
    return "" unless name_node
    name = Noir::TreeSitter.node_text(name_node, source)
    return "" if name.empty?

    object = Noir::TreeSitter.field(call, "object")
    return name if object.nil?

    receiver = receiver_text(object, source)
    return "" if receiver.empty? # chained-on-call or unsupported receiver
    "#{receiver}.#{name}"
  end

  # Reconstruct a dotted receiver text from `identifier` / `field_access`
  # / `this` / `super` nodes. Drops receivers rooted on another
  # call_expression (`foo().bar`) or other non-identifier shapes,
  # mirroring the chained-call-noise filter used by the Python and
  # Go extractors.
  private def receiver_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier", "this", "super"
      Noir::TreeSitter.node_text(node, source)
    when "field_access"
      object = Noir::TreeSitter.field(node, "object")
      field = Noir::TreeSitter.field(node, "field")
      return "" unless object && field
      inner = receiver_text(object, source)
      inner.empty? ? "" : "#{inner}.#{Noir::TreeSitter.node_text(field, source)}"
    else
      ""
    end
  end

  private def find_method(root : LibTreeSitter::TSNode,
                          source : String,
                          class_name : String,
                          method_name : String) : LibTreeSitter::TSNode?
    result : LibTreeSitter::TSNode? = nil
    walk_class_decls(root) do |decl|
      next if result
      name_node = Noir::TreeSitter.field(decl, "name")
      next unless name_node
      next unless Noir::TreeSitter.node_text(name_node, source) == class_name
      body = Noir::TreeSitter.field(decl, "body")
      next unless body
      Noir::TreeSitter.each_named_child(body) do |member|
        next if result
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        mn = Noir::TreeSitter.field(member, "name")
        next unless mn
        result = member if Noir::TreeSitter.node_text(mn, source) == method_name
      end
    end
    result
  end

  private def walk_class_decls(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    ty = Noir::TreeSitter.node_type(node)
    block.call(node) if ty == "class_declaration" || ty == "interface_declaration"
    Noir::TreeSitter.each_named_child(node) do |child|
      walk_class_decls(child, &block)
    end
  end

  private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    block.call(node)
    Noir::TreeSitter.each_named_child(node) do |child|
      walk(child, &block)
    end
  end
end
