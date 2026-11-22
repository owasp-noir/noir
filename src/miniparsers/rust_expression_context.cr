require "../ext/tree_sitter/tree_sitter"

module Noir::RustExpressionContext
  # Yield whole statements except for the impossible arms of a top-level
  # match on the named argument. Dynamic patterns and surrounding code stay
  # in the scan. Stop narrowing if a let binding shadows the argument.
  def self.each_reachable_branch(body : LibTreeSitter::TSNode, source : String, argument : String,
                                 subject : String, excluded_patterns : Array(String), &)
    if excluded_patterns.empty? || !immutable_argument?(body, source, argument)
      yield body
      return
    end

    shadowed = false
    Noir::TreeSitter.each_named_child(body) do |statement|
      node = statement
      if Noir::TreeSitter.node_type(node) == "expression_statement"
        node = Noir::TreeSitter.first_named_child(node) || node
      end
      if Noir::TreeSitter.node_type(node) == "let_declaration" && (pattern = Noir::TreeSitter.field(node, "pattern"))
        shadowed ||= Noir::TreeSitter.node_text(pattern, source).includes?(argument)
      end
      value = Noir::TreeSitter.field(node, "value")
      if !shadowed && Noir::TreeSitter.node_type(node) == "match_expression" && value &&
         Noir::TreeSitter.node_text(value, source) == subject && (arms = Noir::TreeSitter.field(node, "body"))
        Noir::TreeSitter.each_named_child(arms) do |arm|
          pattern = Noir::TreeSitter.field(arm, "pattern")
          yield arm unless pattern && excluded_patterns.includes?(Noir::TreeSitter.node_text(pattern, source))
        end
      else
        yield statement
      end
    end
  end

  private def self.immutable_argument?(body : LibTreeSitter::TSNode, source : String, argument : String) : Bool
    fn = Noir::TreeSitter.parent(body) || return false
    params = Noir::TreeSitter.field(fn, "parameters") || return false
    Noir::TreeSitter.each_named_child(params) do |param|
      pattern = Noir::TreeSitter.field(param, "pattern") || next
      # A plain immutable parameter has just its pattern and type.
      return true if LibTreeSitter.ts_node_named_child_count(param) == 2 && Noir::TreeSitter.node_text(pattern, source) == argument
    end
    false
  end

  # The annotated let binding receiving this call's result. Follow only
  # operations that unwrap the value; a call passed to a helper or used
  # as a fallback argument need not produce the enclosing binding's type.
  def self.bound_type(call : LibTreeSitter::TSNode, source : String) : String?
    value = call
    while parent = Noir::TreeSitter.parent(value)
      case Noir::TreeSitter.node_type(parent)
      when "let_declaration"
        return unless Noir::TreeSitter.field(parent, "value").try(&.id) == value.id
        type = Noir::TreeSitter.field(parent, "type") || return
        return Noir::TreeSitter.node_text(type, source)
      when "await_expression", "try_expression", "parenthesized_expression"
        value = parent
      when "field_expression"
        field = Noir::TreeSitter.field(parent, "field") || return
        return unless {"unwrap", "expect"}.includes?(Noir::TreeSitter.node_text(field, source))
        wrapper = Noir::TreeSitter.parent(parent) || return
        return unless Noir::TreeSitter.node_type(wrapper) == "call_expression"
        value = wrapper
      else
        return
      end
    end
  end
end
