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
#   2. Walk its body for `method_invocation` / `method_reference` nodes.
#   3. For each, reconstruct a textual callee:
#        * `foo()`              → `foo`
#        * `service.save(x)`    → `service.save`
#        * `this.foo()`         → `this.foo`
#        * `Foo.bar()` (static) → `Foo.bar`
#        * `Message::body`      → `Message.body`
#        * `this::toDto`        → `this.toDto`
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
                        method_name : String,
                        target_line : Int32? = nil,
                        decl_index : Hash(String, Int32?)? = nil,
                        method_index : MethodIndex? = nil) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    return sink if class_name.empty? || method_name.empty?

    method_node = find_method(method_index || build_method_index(root, source, class_name), class_name, method_name, target_line)
    return sink unless method_node
    body = Noir::TreeSitter.field(method_node, "body")
    return sink unless body

    # The method-declaration index is file-scoped; callers that resolve
    # callees for many routes in one file (spring.cr) build it once and
    # pass it in. The nil default recomputes it, preserving every other
    # call site.
    resolved_decl_index = decl_index || build_method_decl_index(root, source)

    Noir::TreeSitter.walk(body) do |n|
      node_type = Noir::TreeSitter.node_type(n)
      next unless node_type == "method_invocation" || node_type == "method_reference"
      name = callee_text(n, source)
      next if name.empty?
      row = Noir::TreeSitter.node_start_row(n)
      resolved_line = resolve_same_file_line(n, source, resolved_decl_index)
      sink << {name, file_path, resolved_line || (row + 1)}
    end
    sink
  end

  # `callees_in_method` for many handlers of one parsed file. Each call
  # without `decl_index:` / `method_index:` walks the whole tree twice to
  # build them, so a class with N actions resolved one by one cost O(N²)
  # (Struts2, 4000 `@Action` methods: 36s under `--ai-context`). This
  # builds both on first use and reuses them. Only valid while the tree
  # `root` belongs to is alive — inside the `parse_java` block.
  class FileCallees
    @decl_index : Hash(String, Int32?)?
    @method_index : MethodIndex?

    def initialize(@root : LibTreeSitter::TSNode, @source : String, @file_path : String)
    end

    def callees_in_method(class_name : String, method_name : String, target_line : Int32? = nil) : Array(Tuple(String, String, Int32))
      decl_index = @decl_index ||= JavaCalleeExtractor.build_method_decl_index(@root, @source)
      method_index = @method_index ||= JavaCalleeExtractor.build_method_index(@root, @source)
      JavaCalleeExtractor.callees_in_method(@root, @source, @file_path, class_name, method_name, target_line,
        decl_index: decl_index, method_index: method_index)
    end
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
    callees_in_body(body, source, file_path)
  end

  # Generic body walker for analyzers/extractors that already have the
  # handler method/lambda body node. Returns every 1-hop
  # `method_invocation` callee inside that body.
  def callees_in_body(body : LibTreeSitter::TSNode,
                      source : String,
                      file_path : String) : Array(Tuple(String, String, Int32))
    sink = [] of Tuple(String, String, Int32)
    Noir::TreeSitter.walk(body) do |n|
      node_type = Noir::TreeSitter.node_type(n)
      next unless node_type == "method_invocation" || node_type == "method_reference"
      name = callee_text(n, source)
      next if name.empty?
      row = Noir::TreeSitter.node_start_row(n)
      sink << {name, file_path, row + 1}
    end
    sink
  end

  # ---- private helpers -----------------------------------------------

  private def callee_text(call : LibTreeSitter::TSNode, source : String) : String
    if Noir::TreeSitter.node_type(call) == "method_reference"
      return method_reference_text(call, source)
    end

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

  private def method_reference_text(ref : LibTreeSitter::TSNode, source : String) : String
    receiver, name = method_reference_parts(ref, source)
    return "" if receiver.empty? || name.empty?

    "#{receiver}.#{name}"
  end

  private def method_reference_parts(ref : LibTreeSitter::TSNode, source : String) : Tuple(String, String)
    text = Noir::TreeSitter.node_text(ref, source).strip
    pieces = text.split("::", 2)
    return {"", ""} unless pieces.size == 2

    receiver = pieces[0].strip.gsub(/\s+/, "")
    name = pieces[1].strip.gsub(/\A<[^>]+>\s*/, "")
    # Match the chained-call filter used for method invocations:
    # `factory()::build` is a call-chain continuation, not a clean 1-hop
    # callee target.
    return {"", ""} if receiver.empty? || receiver.includes?("(")
    return {"", ""} if name.empty?

    {receiver, name}
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
      inner = Noir::TreeSitter.descend { receiver_text(object, source) } || ""
      inner.empty? ? "" : "#{inner}.#{Noir::TreeSitter.node_text(field, source)}"
    else
      ""
    end
  end

  # Every `method_declaration` directly in a class or interface body, by
  # `{class name, method name}`, in tree order. Spring resolves callees for
  # every route of a file against one root, and walking the whole tree per
  # route made a controller with N handlers cost O(N²) — build it once and
  # pass it as `method_index:`, like `decl_index:`. `only_class` indexes
  # just that class, for a caller resolving a single method.
  alias MethodIndex = Hash(Tuple(String, String), Array(LibTreeSitter::TSNode))

  def build_method_index(root : LibTreeSitter::TSNode, source : String, only_class : String? = nil) : MethodIndex
    index = MethodIndex.new
    walk_class_decls(root) do |decl|
      name_node = Noir::TreeSitter.field(decl, "name")
      next unless name_node
      class_name = Noir::TreeSitter.node_text(name_node, source)
      next if only_class && class_name != only_class
      body = Noir::TreeSitter.field(decl, "body")
      next unless body
      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        mn = Noir::TreeSitter.field(member, "name")
        next unless mn
        (index[{class_name, Noir::TreeSitter.node_text(mn, source)}] ||= [] of LibTreeSitter::TSNode) << member
      end
    end
    index
  end

  # `target_line` (0-based row of the route's mapping annotation, when
  # available) disambiguates overloaded handlers: the annotation lives
  # inside the correct overload's node span, so the method whose
  # `[start_row, end_row]` range contains that line wins. Falls back to
  # the first same-named method otherwise, matching prior behaviour.
  private def find_method(index : MethodIndex,
                          class_name : String,
                          method_name : String,
                          target_line : Int32? = nil) : LibTreeSitter::TSNode?
    candidates = index[{class_name, method_name}]?
    return unless candidates
    if line = target_line
      matched = candidates.find do |member|
        line >= Noir::TreeSitter.node_start_row(member) && line <= Noir::TreeSitter.node_end_row(member)
      end
      return matched if matched
    end
    candidates.first
  end

  private def walk_class_decls(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    ty = Noir::TreeSitter.node_type(node)
    block.call(node) if ty == "class_declaration" || ty == "interface_declaration"
    Noir::TreeSitter.each_named_child(node) do |child|
      walk_class_decls(child, &block)
    end
  end

  # Build a same-file method-name -> start row map. `nil` value marks
  # an ambiguous name (multiple `method_declaration`s share it), so the
  # caller knows to keep the call site location instead of guessing
  # which overload to point at. Conservative by design — overloads,
  # qualified non-`this` calls, and missing declarations all stay at
  # call site.
  def build_method_decl_index(root : LibTreeSitter::TSNode,
                              source : String) : Hash(String, Int32?)
    index = {} of String => Int32?
    Noir::TreeSitter.walk(root) do |n|
      next unless Noir::TreeSitter.node_type(n) == "method_declaration"
      name_node = Noir::TreeSitter.field(n, "name")
      next unless name_node
      name = Noir::TreeSitter.node_text(name_node, source)
      next if name.empty?
      if index.has_key?(name)
        index[name] = nil # ambiguous: skip resolution for this name
      else
        index[name] = Noir::TreeSitter.node_start_row(n)
      end
    end
    index
  end

  # Resolve a `method_invocation` to a same-file `method_declaration`
  # line (1-based) only when the call is unambiguous:
  #   - unqualified `foo(...)` (no `object` field), or
  #   - `this.foo(...)` (object is the literal `this`),
  #   - `this::foo` method reference,
  # AND the same-file declaration map contains exactly one match.
  # Returns `nil` for qualified non-`this` calls, ambiguous names, and
  # names with no matching same-file declaration — callers fall back to
  # the call site row.
  private def resolve_same_file_line(call : LibTreeSitter::TSNode,
                                     source : String,
                                     decl_index : Hash(String, Int32?)) : Int32?
    if Noir::TreeSitter.node_type(call) == "method_reference"
      receiver, name = method_reference_parts(call, source)
      return unless receiver == "this"
      return resolve_decl_line(name, decl_index)
    end

    name_node = Noir::TreeSitter.field(call, "name")
    return unless name_node
    name = Noir::TreeSitter.node_text(name_node, source)
    return if name.empty?

    object = Noir::TreeSitter.field(call, "object")
    unless object.nil?
      return unless Noir::TreeSitter.node_type(object) == "this"
    end

    resolve_decl_line(name, decl_index)
  end

  private def resolve_decl_line(name : String, decl_index : Hash(String, Int32?)) : Int32?
    return unless decl_index.has_key?(name)
    row = decl_index[name]
    return if row.nil?
    row + 1
  end
end
