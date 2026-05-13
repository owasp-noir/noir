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
  FALLBACK_RESERVED_CALLEES = Set{
    "catch",
    "for",
    "function",
    "if",
    "return",
    "switch",
    "while",
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

  def callees_for_function_body(body : String,
                                file_path : String,
                                open_brace_line : Int32,
                                *,
                                language : Symbol = :javascript) : Array(Entry)
    wrapper = "function __noir_handler__() {#{body}\n}"
    sink = [] of Entry

    Noir::TreeSitter.parse_javascript(wrapper) do |root|
      walk_first_function_body(root, wrapper, file_path, sink, 0)
    end

    if sink.empty? && language == :typescript
      return fallback_callees_for_function_body(body, file_path, open_brace_line)
    end

    sink.map do |name, path, line|
      {name, path, open_brace_line + line - 1}
    end
  rescue
    language == :typescript ? fallback_callees_for_function_body(body, file_path, open_brace_line) : [] of Entry
  end

  def callees_for_exported_function(source : String,
                                    file_path : String,
                                    export_name : String) : Array(Entry)
    source_for_ast = normalize_exported_handler_source(source)
    sink = [] of Entry
    Noir::TreeSitter.parse_javascript(source_for_ast) do |root|
      if handler = exported_handler(root, root, source_for_ast, export_name, 0)
        walk_callees(handler_body(handler), source_for_ast, file_path, sink, 0)
      end
    end

    dedup_entries(sink)
  rescue
    [] of Entry
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
    sink = [] of Entry
    walk_callees(handler_body(handler), source, file_path, sink, 0)
    sink
  end

  private def normalize_exported_handler_source(source : String) : String
    # The vendored JavaScript grammar still exposes useful nodes for many
    # TypeScript files, but `const GET: RequestHandler = ...` makes the
    # variable name parse as the type. Strip same-line annotations while
    # preserving line numbers so AST row-based callee locations stay valid.
    source.gsub(/(\b(?:export\s+)?(?:const|let|var)\s+[A-Za-z_$][\w$]*)\s*:\s*[^=\n]+=/, "\\1 =")
  end

  private def exported_handler(root : LibTreeSitter::TSNode,
                               node : LibTreeSitter::TSNode,
                               source : String,
                               export_name : String,
                               depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "export_statement"
      if declaration = Noir::TreeSitter.field(node, "declaration")
        if handler = declaration_handler(declaration, source, export_name)
          return handler
        end
      elsif local_name = export_clause_local_name(node, source, export_name)
        return local_handler(root, source, local_name, 0)
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      if handler = exported_handler(root, child, source, export_name, depth + 1)
        return handler
      end
    end
  end

  private def declaration_handler(node : LibTreeSitter::TSNode,
                                  source : String,
                                  name : String) : LibTreeSitter::TSNode?
    if handler_node?(node)
      node_name = Noir::TreeSitter.field(node, "name")
      return node if node_name && Noir::TreeSitter.node_text(node_name, source) == name
    end

    variable_handler(node, source, name, 0)
  end

  private def local_handler(node : LibTreeSitter::TSNode,
                            source : String,
                            name : String,
                            depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if handler_node?(node)
      node_name = Noir::TreeSitter.field(node, "name")
      return node if node_name && Noir::TreeSitter.node_text(node_name, source) == name
    end

    if handler = variable_handler(node, source, name, depth)
      return handler
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      if handler = local_handler(child, source, name, depth + 1)
        return handler
      end
    end
  end

  private def variable_handler(node : LibTreeSitter::TSNode,
                               source : String,
                               name : String,
                               depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "variable_declarator"
      node_name = Noir::TreeSitter.field(node, "name")
      if node_name && Noir::TreeSitter.node_text(node_name, source) == name
        value = Noir::TreeSitter.field(node, "value")
        return value if value && handler_node?(value)
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      if handler = variable_handler(child, source, name, depth + 1)
        return handler
      end
    end
  end

  private def export_clause_local_name(node : LibTreeSitter::TSNode,
                                       source : String,
                                       export_name : String) : String?
    Noir::TreeSitter.each_named_child(node) do |child|
      if Noir::TreeSitter.node_type(child) == "export_clause"
        Noir::TreeSitter.each_named_child(child) do |specifier|
          next unless Noir::TreeSitter.node_type(specifier) == "export_specifier"

          name = Noir::TreeSitter.field(specifier, "name")
          alias_name = Noir::TreeSitter.field(specifier, "alias")
          exported = alias_name || name
          next unless name && exported
          next unless Noir::TreeSitter.node_text(exported, source) == export_name

          return Noir::TreeSitter.node_text(name, source)
        end
      end
    end
  end

  private def handler_body(handler : LibTreeSitter::TSNode) : LibTreeSitter::TSNode
    Noir::TreeSitter.field(handler, "body") || handler
  end

  private def handler_node?(node : LibTreeSitter::TSNode) : Bool
    case Noir::TreeSitter.node_type(node)
    when "function_declaration", "function_expression", "arrow_function"
      true
    else
      false
    end
  end

  private def walk_first_function_body(node : LibTreeSitter::TSNode,
                                       source : String,
                                       file_path : String,
                                       sink : Array(Entry),
                                       depth : Int32) : Bool
    return false if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "function_declaration"
      if body = Noir::TreeSitter.field(node, "body")
        walk_callees(body, source, file_path, sink, 0)
        return true
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      return true if walk_first_function_body(child, source, file_path, sink, depth + 1)
    end

    false
  end

  private def fallback_callees_for_function_body(body : String, file_path : String, open_brace_line : Int32) : Array(Entry)
    entries = [] of Entry

    body.each_line.with_index do |line, index|
      line.scan(/((?:this|super|[A-Za-z_$][\w$]*)(?:\s*\(\s*\))?(?:\.[A-Za-z_$][\w$]*(?:\s*\(\s*\))?)*)\s*\(/) do |match|
        next unless match.size > 1

        name = match[1].gsub(/\s+/, "")
        next if name.empty? || FALLBACK_RESERVED_CALLEES.includes?(name)

        entries << {name, file_path, open_brace_line + index}
      end
    end

    dedup_entries(entries)
  end

  private def walk_callees(node : LibTreeSitter::TSNode,
                           source : String,
                           file_path : String,
                           sink : Array(Entry),
                           depth : Int32)
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    skip_function_child : LibTreeSitter::TSNode? = nil
    if Noir::TreeSitter.node_type(node) == "call_expression"
      name = callee_text(node, source)
      unless name.empty?
        line = Noir::TreeSitter.node_start_row(node) + 1
        sink << {name, file_path, line}
        skip_function_child = Noir::TreeSitter.field(node, "function") || first_named_child(node)
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      next if skip_function_child && same_node?(child, skip_function_child)

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

  private def same_node?(left : LibTreeSitter::TSNode, right : LibTreeSitter::TSNode) : Bool
    LibTreeSitter.ts_node_start_byte(left) == LibTreeSitter.ts_node_start_byte(right) &&
      LibTreeSitter.ts_node_end_byte(left) == LibTreeSitter.ts_node_end_byte(right)
  end

  private def dedup_entries(entries : Array(Entry)) : Array(Entry)
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
