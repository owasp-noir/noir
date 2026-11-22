require "../ext/tree_sitter/tree_sitter"

module Noir::RailsDeviseProviders
  # Resolve only a complete, literal provider option on the model. A computed
  # item, conditional declaration or second configuration keeps the wildcard.
  def self.resolve(source : String, model : String) : Array(String)?
    return unless source.includes?("omniauth_providers")
    configurations = [] of Array(String)?
    Noir::TreeSitter.parse_ruby(source) do |root|
      return if Noir::TreeSitter.node_has_error?(root)
      Noir::TreeSitter.walk(root) do |call|
        # An accessor override or mutation can replace/extend the literal list.
        if Noir::TreeSitter.node_type(call) == "identifier" && Noir::TreeSitter.node_text(call, source) == "omniauth_providers"
          configurations << nil
        end
        next unless Noir::TreeSitter.node_type(call) == "call"
        next unless method = Noir::TreeSitter.field(call, "method")
        next unless Noir::TreeSitter.node_text(method, source) == "devise"
        next unless args = Noir::TreeSitter.field(call, "arguments")
        Noir::TreeSitter.each_named_arg(args) do |pair|
          configurations << nil if Noir::TreeSitter.node_type(pair) == "hash_splat_argument"
          next unless Noir::TreeSitter.node_type(pair) == "pair"
          next unless key = Noir::TreeSitter.field(pair, "key")
          next unless Noir::TreeSitter.node_text(key, source).lchop(':') == "omniauth_providers"
          configurations << direct_model_list(call, pair, source, model)
        end
      end
    end
    configurations.first? if configurations.size == 1
  rescue
    nil
  end

  private def self.direct_model_list(call, pair, source, model) : Array(String)?
    return if Noir::TreeSitter.field(call, "receiver")
    body = Noir::TreeSitter.parent(call)
    klass = body.try { |node| Noir::TreeSitter.parent(node) }
    return unless klass && Noir::TreeSitter.node_type(klass) == "class"
    outer = Noir::TreeSitter.parent(klass)
    return unless outer && Noir::TreeSitter.node_type(outer) == "program"
    name = Noir::TreeSitter.field(klass, "name")
    return unless name && Noir::TreeSitter.node_text(name, source) == model
    value = Noir::TreeSitter.field(pair, "value")
    literal_names(value, source) if value
  end

  private def self.literal_names(value : LibTreeSitter::TSNode, source : String) : Array(String)?
    return unless {"array", "symbol_array", "string_array"}.includes?(Noir::TreeSitter.node_type(value))
    names = [] of String
    Noir::TreeSitter.each_named_arg(value) do |item|
      name = Noir::TreeSitter.node_text(item, source)
      case Noir::TreeSitter.node_type(item)
      when "simple_symbol" then name = name.lchop(':')
      when "string"        then name = name[1...-1]
      when "bare_symbol", "bare_string"
      else
        return
      end
      return unless name.matches?(/\A[\w-]+\z/)
      names << name
    end
    names.uniq
  end
end
