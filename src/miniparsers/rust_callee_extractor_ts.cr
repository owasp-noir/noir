require "../ext/tree_sitter/tree_sitter"
require "./callee_extractor_base"

# Tree-sitter-backed Rust callee extractor. Replaces the regex
# line-scanner in `Noir::RustCalleeExtractor` with an AST walker over
# the vendored `tree-sitter-rust` grammar. Catches calls that span
# lines, sees through string/comment context for free (the parser
# already does that), and exposes a parse-once entry point so analyzers
# can share a single parsed tree per file.
#
# Three call shapes are recognised, mirroring the legacy extractor:
#
#   1. Path call            `Foo::bar(...)`        → "Foo::bar"
#   2. Receiver chain       `obj.users.find(...)`  → "obj.users.find"
#   3. Bare call            `foo(...)`             → "foo"
#   4. Macro invocation     `println!(...)`        → "println!"
#                           `std::format!(...)`    → "std::format!"
#
# Receivers rooted on another call result (`foo().bar()`) are dropped
# as noise — same convention used by `Noir::JavaCalleeExtractor` and
# `Noir::GoCalleeExtractor`.
module Noir::RustCalleeExtractorTS
  extend self
  include Noir::CalleeExtractorBase

  # Rust keywords + commonly-aliased control-flow constructors that
  # surface as `call_expression`s but carry no useful callee signal.
  # Kept in sync with the legacy regex extractor's `RESERVED` set so
  # callers see no behaviour change when swapping the implementation.
  RESERVED = Set{
    "as", "async", "await", "break", "const", "continue", "crate",
    "dyn", "else", "enum", "extern", "false", "fn", "for", "if",
    "impl", "in", "let", "loop", "match", "mod", "move", "mut",
    "pub", "ref", "return", "self", "Self", "static", "struct",
    "super", "trait", "true", "type", "unsafe", "use", "where",
    "while", "Ok", "Err", "Some", "None", "format", "format!",
    "vec", "vec!", "println", "println!",
  }

  # Walk `body` (typically a `block` from a `function_item`'s `body`
  # field, but any subtree works) and return every callee inside.
  # Line numbers are taken straight from the tree-sitter node row, so
  # `source` must be the *full file text* that was parsed — callers
  # using a wrapper or sub-extract should use `callees_for_body_text`
  # instead.
  def callees_in_body(body : LibTreeSitter::TSNode,
                      source : String,
                      file_path : String) : Array(Entry)
    sink = [] of Entry
    walk(body) do |node|
      case Noir::TreeSitter.node_type(node)
      when "call_expression"
        name = call_callee_text(node, source)
        push_entry(sink, name, file_path, node) if name
      when "macro_invocation"
        name = macro_callee_text(node, source)
        push_entry(sink, name, file_path, node) if name
      end
    end
    dedup(sink)
  end

  # Drop-in replacement for `Noir::RustCalleeExtractor.callees_for_body`.
  # Wraps `body_text` in a synthetic `fn _() { ... }` so the grammar
  # has a complete top-level item to parse, then translates wrapper-
  # relative rows back to file-relative ones (`start_line` is the
  # 1-based file line of the body's first line).
  #
  # This shim exists for back-compat with the existing engine that
  # extracts function bodies as raw text. New code should parse the
  # file once and call `callees_in_body` with the body node directly.
  def callees_for_body_text(body_text : String,
                            file_path : String,
                            start_line : Int32) : Array(Entry)
    return [] of Entry if body_text.empty?

    wrapped = String.build do |io|
      io << "fn __noir_wrap__() {\n"
      io << body_text
      io << "\n}\n"
    end

    raw = [] of Entry
    Noir::TreeSitter.parse_rust(wrapped) do |root|
      fn_node = first_function_item(root)
      next unless fn_node
      body_node = Noir::TreeSitter.field(fn_node, "body")
      next unless body_node
      raw = callees_in_body(body_node, wrapped, file_path)
    end

    # Wrapper row 1 == body_text line 0 == file line `start_line`.
    # `raw`'s line is `row + 1`, so subtract the wrapper preamble row
    # (1) and the +1 row offset to get the body-relative index, then
    # add `start_line` to land at the file row.
    raw.map { |name, path, line| {name, path, start_line + line - 2} }
  end

  # ---- private helpers -----------------------------------------------

  private def push_entry(sink : Array(Entry),
                         name : String,
                         file_path : String,
                         node : LibTreeSitter::TSNode) : Nil
    return if skip_callee?(name)
    sink << {name, file_path, Noir::TreeSitter.node_start_row(node) + 1}
  end

  # Reconstruct callee text from a `call_expression`'s `function` field.
  # Returns `nil` when the callee is rooted on a non-identifier shape
  # (call result, parenthesised expression, …) so the walker drops it.
  private def call_callee_text(call : LibTreeSitter::TSNode, source : String) : String?
    fn_node = Noir::TreeSitter.field(call, "function")
    return unless fn_node
    callee_text_from(fn_node, source)
  end

  private def callee_text_from(node : LibTreeSitter::TSNode, source : String) : String?
    case Noir::TreeSitter.node_type(node)
    when "identifier", "scoped_identifier"
      Noir::TreeSitter.node_text(node, source)
    when "field_expression"
      receiver_chain(node, source)
    when "generic_function"
      # `foo::<T>()` — peel the turbofish and try again on the inner
      # path/identifier.
      inner = Noir::TreeSitter.field(node, "function")
      inner ? callee_text_from(inner, source) : nil
    end
  end

  # Reconstruct `a.b.c` style receivers. Returns `nil` once the chain
  # hits a non-identifier root (call_expression, parenthesised_expression,
  # …) so chained-on-call noise (`foo().bar`) gets dropped.
  private def receiver_chain(node : LibTreeSitter::TSNode, source : String) : String?
    case Noir::TreeSitter.node_type(node)
    when "identifier", "scoped_identifier", "self"
      Noir::TreeSitter.node_text(node, source)
    when "field_expression"
      value = Noir::TreeSitter.field(node, "value")
      field = Noir::TreeSitter.field(node, "field")
      return unless value && field
      inner = receiver_chain(value, source)
      return unless inner
      "#{inner}.#{Noir::TreeSitter.node_text(field, source)}"
    end
  end

  # `println!(...)`, `std::format!(...)`. The trailing `!` is added so
  # the result matches the legacy regex extractor's output verbatim.
  private def macro_callee_text(macro_inv : LibTreeSitter::TSNode, source : String) : String?
    name_node = Noir::TreeSitter.field(macro_inv, "macro")
    return unless name_node
    case Noir::TreeSitter.node_type(name_node)
    when "identifier", "scoped_identifier"
      "#{Noir::TreeSitter.node_text(name_node, source)}!"
    end
  end

  # Mirrors the legacy `RustCalleeExtractor#skip_callee?`. Keeps
  # namespaced calls whose last segment happens to be a reserved
  # wrapper (`HttpResponse::Ok`) while still dropping `std::format!`
  # style noise.
  private def skip_callee?(name : String) : Bool
    return true if name.empty?
    last = name.split('.').last.split("::").last
    RESERVED.includes?(last) && (!name.includes?("::") || last.includes?('!'))
  end

  private def dedup(entries : Array(Entry)) : Array(Entry)
    seen = Set(String).new
    entries.select do |name, path, line|
      key = "#{name}\0#{path}\0#{line}"
      if seen.includes?(key)
        false
      else
        seen.add(key)
        true
      end
    end
  end

  private def first_function_item(root : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    found : LibTreeSitter::TSNode? = nil
    Noir::TreeSitter.each_named_child(root) do |child|
      next if found
      found = child if Noir::TreeSitter.node_type(child) == "function_item"
    end
    found
  end

  private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
    block.call(node)
    Noir::TreeSitter.each_named_child(node) do |child|
      walk(child, &block)
    end
  end
end
