require "../ext/tree_sitter/tree_sitter"

module Noir
  # Tree-sitter node helpers shared by the JS/TS framework extractors
  # (AdonisJS, Elysia, Hapi). `include` it into an `extend self` module.
  module JSTSAstHelpers
    # `Route.get(...)` and `app.get(...).post(...)` both produce
    # call_expressions whose callee is a member_expression ending in a
    # `property_identifier`. Return that property name; empty string when
    # the callee is a bare identifier (`foo(...)`, `new Foo()`).
    private def chain_method_name(call : LibTreeSitter::TSNode, source : String) : String
      callee = Noir::TreeSitter.first_named_child(call)
      return "" unless callee
      return "" unless Noir::TreeSitter.node_type(callee) == "member_expression"
      Noir::TreeSitter.each_named_child(callee) do |child|
        return Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "property_identifier"
      end
      ""
    end

    # Collapse a `member_expression` chain into `["a", "b", "c"]`
    # for `a.b.c`. Returns `[""]` on any non-identifier piece
    # (function calls, computed properties, etc.).
    private def navigation_chain(node : LibTreeSitter::TSNode, source : String) : Array(String)
      chain = [] of String
      collect_chain(node, source, chain)
      chain
    end

    private def collect_chain(node : LibTreeSitter::TSNode, source : String, chain : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "identifier"
        chain << Noir::TreeSitter.node_text(node, source)
      when "member_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          ty = Noir::TreeSitter.node_type(child)
          case ty
          when "identifier", "member_expression"
            collect_chain(child, source, chain)
          when "property_identifier"
            chain << Noir::TreeSitter.node_text(child, source)
          else
            chain.clear
            chain << ""
            return
          end
        end
      else
        chain.clear
        chain << ""
      end
    end

    private def subscript_string_key(node : LibTreeSitter::TSNode, source : String) : String?
      seen_target = false
      Noir::TreeSitter.each_named_child(node) do |child|
        if !seen_target
          seen_target = true
          next
        end
        child = Noir::TreeSitter.unwrap_expression(child)
        if Noir::TreeSitter.node_type(child) == "string"
          return decode_string(child, source)
        end
      end
      nil
    end

    private def arguments_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "arguments"
      end
      nil
    end

    # tree-sitter-javascript wraps string contents in
    # `string_fragment` named children — template literals included —
    # with each escape as an `escape_sequence` sibling.
    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          when "escape_sequence"
            io << Noir::TreeSitter.unescape(Noir::TreeSitter.node_text(child, source))
          when "template_substitution"
            # `` `/users/${id}` `` — keep the hole as a `{id}` placeholder
            # rather than dropping it, which would collapse the path to
            # `/users/` (or `/users//edit` for an interior hole). Same
            # convention the Python f-string and Kotlin template decoders
            # use, and the shape downstream path-param extraction expects.
            io << Noir::TreeSitter.node_text(child, source).lchop('$')
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      if raw.size >= 2 && (raw[0] == '\'' || raw[0] == '"' || raw[0] == '`') && raw[0] == raw[-1]
        raw[1..-2]
      else
        raw
      end
    end
  end
end
