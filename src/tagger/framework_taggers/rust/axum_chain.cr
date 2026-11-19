require "../../../ext/tree_sitter/tree_sitter"

# Reads an axum `Router` builder chain (`Router::new().route(..).layer(..)`)
# off the tree-sitter syntax tree. Shared by the Rust auth and security
# taggers, which both need to know which routes a `.layer(..)` wraps.
module RustAxumChain
  # The method name of `recv.name(..)`, nil for a plain call.
  private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
    fn_node = Noir::TreeSitter.field(call, "function")
    return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
    field = Noir::TreeSitter.field(fn_node, "field")
    field ? Noir::TreeSitter.node_text(field, source) : nil
  end

  # `recv` of `recv.name(..)`.
  private def chain_receiver(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    fn_node = Noir::TreeSitter.field(call, "function")
    return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
    Noir::TreeSitter.field(fn_node, "value")
  end

  private def call_func_full_text(call : LibTreeSitter::TSNode, source : String) : String
    fn_node = Noir::TreeSitter.field(call, "function")
    fn_node ? Noir::TreeSitter.node_text(fn_node, source).strip : ""
  end

  private def named_call_args(call : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
    args = [] of LibTreeSitter::TSNode
    if arg_list = Noir::TreeSitter.field(call, "arguments")
      Noir::TreeSitter.each_named_arg(arg_list) do |arg|
        args << arg
      end
    end
    args
  end

  private def string_literal_content(node : LibTreeSitter::TSNode, source : String) : String?
    return unless Noir::TreeSitter.node_type(node) == "string_literal"
    raw = Noir::TreeSitter.node_text(node, source)
    if raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2
      raw[1...-1]
    elsif m = raw.match(/\Ar#*"(.*)"#*\z/m)
      m[1]
    end
  end

  # The `.route("/p", get(h).layer(x))` whose method router `call` sits in:
  # that layer wraps the one route.
  private def find_enclosing_route_call(call : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
    node = call
    while parent = Noir::TreeSitter.parent(node)
      if Noir::TreeSitter.node_type(parent) == "call_expression"
        if field_call_name(parent, source) == "route"
          args = named_call_args(parent)
          if args.size >= 2
            arg1_start = LibTreeSitter.ts_node_start_byte(args[1]).to_i
            call_start = LibTreeSitter.ts_node_start_byte(call).to_i
            if call_start >= arg1_start
              return parent
            end
          end
        end
      end
      node = parent
    end
    nil
  end
end
