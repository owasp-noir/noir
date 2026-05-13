require "../ext/tree_sitter/tree_sitter"

module Noir::JSCalleeExtractor
  extend self

  HTTP_VERB_METHODS = {
    "get"     => "GET",
    "post"    => "POST",
    "put"     => "PUT",
    "delete"  => "DELETE",
    "del"     => "DELETE",
    "patch"   => "PATCH",
    "head"    => "HEAD",
    "options" => "OPTIONS",
    "trace"   => "TRACE",
    "connect" => "CONNECT",
    "all"     => "ALL",
  }

  alias Entry = Tuple(String, String, Int32)

  def callees_for_routes(source : String, file_path : String) : Hash(String, Array(Entry))
    by_route = {} of String => Array(Entry)
    Noir::TreeSitter.parse_javascript(source) do |root|
      walk_routes(root, source, file_path, by_route, 0)
    end
    by_route
  rescue
    {} of String => Array(Entry)
  end

  def route_key(method : String, path : String, line : Int32) : String
    "#{method.upcase}::#{path}::#{line}"
  end

  private def walk_routes(node : LibTreeSitter::TSNode,
                          source : String,
                          file_path : String,
                          by_route : Hash(String, Array(Entry)),
                          depth : Int32)
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "call_expression"
      route_info = route_info_for_call(node, source)
      if route_info
        method, path, handler = route_info
        line = Noir::TreeSitter.node_start_row(node) + 1
        by_route[route_key(method, path, line)] = callees_in_handler(handler, source, file_path)
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      walk_routes(child, source, file_path, by_route, depth + 1)
    end
  end

  private def route_info_for_call(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String, LibTreeSitter::TSNode)?
    method = call_method_name(call, source)
    return unless HTTP_VERB_METHODS.has_key?(method) || method == "on"

    args = arguments_node(call)
    return unless args

    if method == "on"
      return on_route_info(args, source)
    end

    path : String? = nil
    handler : LibTreeSitter::TSNode? = nil
    Noir::TreeSitter.each_named_child(args) do |arg|
      case Noir::TreeSitter.node_type(arg)
      when "string", "template_string"
        path ||= decode_string(arg, source)
      when "arrow_function", "function_expression"
        handler ||= arg
      end
    end
    return unless path && handler

    {HTTP_VERB_METHODS[method], path, handler}
  end

  private def on_route_info(args : LibTreeSitter::TSNode, source : String) : Tuple(String, String, LibTreeSitter::TSNode)?
    strings = [] of String
    handler : LibTreeSitter::TSNode? = nil

    Noir::TreeSitter.each_named_child(args) do |arg|
      case Noir::TreeSitter.node_type(arg)
      when "string", "template_string"
        strings << decode_string(arg, source)
      when "arrow_function", "function_expression"
        handler ||= arg
      end
    end

    return unless strings.size >= 2 && handler
    method = strings[0].upcase
    return unless HTTP_VERB_METHODS.values.includes?(method)

    {method, strings[1], handler}
  end

  private def callees_in_handler(handler : LibTreeSitter::TSNode, source : String, file_path : String) : Array(Entry)
    body = Noir::TreeSitter.field(handler, "body") || handler
    sink = [] of Entry
    walk_callees(body, source, file_path, sink, 0)
    sink
  end

  private def walk_callees(node : LibTreeSitter::TSNode,
                           source : String,
                           file_path : String,
                           sink : Array(Entry),
                           depth : Int32)
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "call_expression"
      name = callee_text(node, source)
      unless name.empty?
        line = Noir::TreeSitter.node_start_row(node) + 1
        sink << {name, file_path, line}
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      walk_callees(child, source, file_path, sink, depth + 1)
    end
  end

  private def callee_text(call : LibTreeSitter::TSNode, source : String) : String
    function = Noir::TreeSitter.field(call, "function") || first_named_child(call)
    return "" unless function

    expression_text(function, source)
  end

  private def expression_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier", "property_identifier"
      Noir::TreeSitter.node_text(node, source)
    when "member_expression"
      object = Noir::TreeSitter.field(node, "object")
      property = Noir::TreeSitter.field(node, "property")
      return "" unless object && property

      receiver = receiver_text(object, source)
      return "" if receiver.empty?

      property_name = expression_text(property, source)
      property_name.empty? ? "" : "#{receiver}.#{property_name}"
    when "parenthesized_expression"
      inner = first_named_child(node)
      inner ? expression_text(inner, source) : ""
    when "sequence_expression"
      last = last_named_child(node)
      last ? expression_text(last, source) : ""
    else
      ""
    end
  end

  private def receiver_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier", "property_identifier", "this", "super"
      Noir::TreeSitter.node_text(node, source)
    when "member_expression"
      expression_text(node, source)
    when "call_expression"
      name = callee_text(node, source)
      name.empty? ? "" : "#{name}()"
    when "parenthesized_expression"
      inner = first_named_child(node)
      inner ? receiver_text(inner, source) : ""
    else
      ""
    end
  end

  private def call_method_name(call : LibTreeSitter::TSNode, source : String) : String
    function = Noir::TreeSitter.field(call, "function") || first_named_child(call)
    return "" unless function
    return "" unless Noir::TreeSitter.node_type(function) == "member_expression"

    property = Noir::TreeSitter.field(function, "property")
    property ? Noir::TreeSitter.node_text(property, source).downcase : ""
  end

  private def arguments_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    Noir::TreeSitter.field(call, "arguments") || begin
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "arguments"
      end
      nil
    end
  end

  private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    child_count = LibTreeSitter.ts_node_named_child_count(node)
    return if child_count == 0

    LibTreeSitter.ts_node_named_child(node, 0)
  end

  private def last_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
    child_count = LibTreeSitter.ts_node_named_child_count(node)
    return if child_count == 0

    LibTreeSitter.ts_node_named_child(node, child_count - 1)
  end

  private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
    fragments = [] of String
    Noir::TreeSitter.each_named_child(node) do |child|
      type = Noir::TreeSitter.node_type(child)
      if type == "string_fragment" || type == "template_chars"
        fragments << Noir::TreeSitter.node_text(child, source)
      end
    end
    return fragments.join unless fragments.empty?

    text = Noir::TreeSitter.node_text(node, source)
    if text.size >= 2
      text[1..-2]
    else
      text
    end
  end
end
