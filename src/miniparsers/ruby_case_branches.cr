require "../ext/tree_sitter/tree_sitter"

module Noir::RubyCaseBranches
  # Project top-level case statements onto their literal string choices.
  # Keep surrounding code (including shared parser assignments), else arms,
  # and any arm that includes an expression we cannot resolve.
  def self.bodies(source : String, receiver : String, method : String, choices : Array(String)) : Hash(String, String)
    result = {} of String => String
    return result unless choices.size > 1 && source.includes?("case")

    excluded = Hash(String, Array(Range(Int32, Int32))).new
    Noir::TreeSitter.parse_ruby(source) do |root|
      next if Noir::TreeSitter.node_has_error?(root) || rebound?(root, receiver, source)
      Noir::TreeSitter.each_named_child(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "case"
        value = Noir::TreeSitter.field(node, "value") || next
        next unless Noir::TreeSitter.node_text(value, source) == "#{receiver}.#{method}"
        Noir::TreeSitter.each_named_child(node) do |arm|
          next unless Noir::TreeSitter.node_type(arm) == "when"
          names = literal_choices(arm, source)
          next if names.empty? || !names.all? { |name| choices.includes?(name) }
          body = Noir::TreeSitter.field(arm, "body") || next
          span = LibTreeSitter.ts_node_start_byte(body).to_i...LibTreeSitter.ts_node_end_byte(body).to_i
          (choices - names).each { |choice| (excluded[choice] ||= [] of Range(Int32, Int32)) << span }
        end
      end
    end

    excluded.each do |choice, spans|
      result[choice] = String.build do |io|
        offset = 0
        spans.each do |span|
          io << source.byte_slice(offset, span.begin - offset) << '\n'
          offset = span.end
        end
        io << source.byte_slice(offset)
      end
    end
    result
  rescue
    {} of String => String
  end

  # Only narrow a case over the block argument while all references are
  # plain reads. Assignments, destructuring and shadowing block parameters
  # can give the same name a different value.
  private def self.rebound?(root : LibTreeSitter::TSNode, receiver : String, source : String) : Bool
    ambiguous = false
    Noir::TreeSitter.walk(root) do |node|
      next unless Noir::TreeSitter.node_type(node) == "identifier" && Noir::TreeSitter.node_text(node, source) == receiver
      parent = Noir::TreeSitter.parent(node) || next
      ambiguous = true unless {"call", "element_reference", "argument_list"}.includes?(Noir::TreeSitter.node_type(parent))
    end
    ambiguous
  end

  private def self.literal_choices(arm : LibTreeSitter::TSNode, source : String) : Array(String)
    names = [] of String
    Noir::TreeSitter.each_named_child(arm) do |child|
      next unless Noir::TreeSitter.node_type(child) == "pattern"
      literal = Noir::TreeSitter.node_text(child, source).match(/\A(['"])([A-Z]+)\1\z/) || return [] of String
      names << literal[2]
    end
    names
  end
end
