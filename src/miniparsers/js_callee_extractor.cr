require "../ext/tree_sitter/tree_sitter"
require "./callee_extractor_base"

module Noir::JSCalleeExtractor
  extend self
  include Noir::CalleeExtractorBase

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
  EVENT_HANDLER_CALLS = Set{
    "defineEventHandler",
    "eventHandler",
    "defineCachedEventHandler",
    "cachedEventHandler",
  }

  alias Definitions = Hash(String, Int32?)

  def callees_for_routes(source : String, file_path : String) : Hash(String, Array(Entry))
    by_route = {} of String => Array(Entry)
    Noir::TreeSitter.parse_javascript(source) do |root|
      definitions = top_level_definitions(root, source)
      walk_routes(root, source, file_path, by_route, 0, definitions)
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

  def callees_for_handler_node(handler : LibTreeSitter::TSNode,
                               source : String,
                               file_path : String) : Array(Entry)
    sink = [] of Entry
    walk_callees(handler_body(handler), source, file_path, sink, 0)
    dedup_entries(sink)
  rescue
    [] of Entry
  end

  def callees_for_exported_function(source : String,
                                    file_path : String,
                                    export_name : String) : Array(Entry)
    source_for_ast = normalize_handler_source(source)
    sink = [] of Entry
    Noir::TreeSitter.parse_javascript(source_for_ast) do |root|
      definitions = top_level_definitions(root, source_for_ast)
      if handler = exported_handler(root, root, source_for_ast, export_name, 0)
        walk_callees(handler_body(handler), source_for_ast, file_path, sink, 0, definitions)
      end
    end

    dedup_entries(sink)
  rescue
    [] of Entry
  end

  def exported_function_line(source : String,
                             export_name : String) : Int32?
    source_for_ast = normalize_handler_source(source)
    line : Int32? = nil
    Noir::TreeSitter.parse_javascript(source_for_ast) do |root|
      if handler = exported_handler(root, root, source_for_ast, export_name, 0)
        line = Noir::TreeSitter.node_start_row(handler) + 1
      end
    end

    line
  rescue
    nil
  end

  def callees_for_default_event_handler(source : String,
                                        file_path : String,
                                        *,
                                        language : Symbol = :javascript) : Array(Entry)
    source_for_ast = normalize_handler_source(source)
    event_handler_calls = event_handler_call_names(source_for_ast)
    sink = [] of Entry
    Noir::TreeSitter.parse_javascript(source_for_ast) do |root|
      definitions = top_level_definitions(root, source_for_ast)
      if handler = exported_event_handler(root, root, source_for_ast, event_handler_calls, 0)
        walk_callees(handler_body(handler), source_for_ast, file_path, sink, 0, definitions)
      end
    end

    dedup_entries(sink)
  rescue
    [] of Entry
  end

  def route_key(method : String, path : String, line : Int32) : String
    "#{method.upcase}::#{path}::#{line}"
  end

  # Collect same-file top-level declarations that we can use to resolve
  # bare-identifier callees to their definition lines. Walks only the
  # program's immediate children (and `export_statement` wrappers); nested
  # scopes are ignored. Names declared more than once are mapped to `nil`
  # so callers can leave ambiguous references at the call site.
  private def top_level_definitions(root : LibTreeSitter::TSNode, source : String) : Definitions
    definitions = Definitions.new
    Noir::TreeSitter.each_named_child(root) do |child|
      collect_top_level_definition(child, source, definitions)
    end
    definitions
  end

  private def collect_top_level_definition(node : LibTreeSitter::TSNode,
                                           source : String,
                                           definitions : Definitions)
    type = Noir::TreeSitter.node_type(node)
    case type
    when "function_declaration", "generator_function_declaration"
      if name_node = Noir::TreeSitter.field(node, "name")
        record_definition(definitions, Noir::TreeSitter.node_text(name_node, source), node)
      end
    when "lexical_declaration", "variable_declaration"
      Noir::TreeSitter.each_named_child(node) do |child|
        next unless Noir::TreeSitter.node_type(child) == "variable_declarator"
        name_node = Noir::TreeSitter.field(child, "name")
        value_node = Noir::TreeSitter.field(child, "value")
        next unless name_node && value_node
        next unless Noir::TreeSitter.node_type(name_node) == "identifier"

        case Noir::TreeSitter.node_type(value_node)
        when "arrow_function", "function_expression"
          record_definition(definitions, Noir::TreeSitter.node_text(name_node, source), child)
        end
      end
    when "export_statement"
      if declaration = Noir::TreeSitter.field(node, "declaration")
        collect_top_level_definition(declaration, source, definitions)
      end
    end
  end

  private def record_definition(definitions : Definitions,
                                name : String,
                                node : LibTreeSitter::TSNode)
    return if name.empty?

    if definitions.has_key?(name)
      definitions[name] = nil
    else
      definitions[name] = Noir::TreeSitter.node_start_row(node) + 1
    end
  end

  private def walk_routes(node : LibTreeSitter::TSNode,
                          source : String,
                          file_path : String,
                          by_route : Hash(String, Array(Entry)),
                          depth : Int32,
                          definitions : Definitions)
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "call_expression"
      route_info = route_info_for_call(node, source)
      if route_info
        method, path, handler = route_info
        callees = callees_in_handler(handler, source, file_path, definitions)
        route_call_lines(node).each do |line|
          by_route[route_key(method, path, line)] = callees
        end
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      walk_routes(child, source, file_path, by_route, depth + 1, definitions)
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

  private def callees_in_handler(handler : LibTreeSitter::TSNode,
                                 source : String,
                                 file_path : String,
                                 definitions : Definitions) : Array(Entry)
    sink = [] of Entry
    walk_callees(handler_body(handler), source, file_path, sink, 0, definitions)
    sink
  end

  private def normalize_handler_source(source : String) : String
    # The vendored JavaScript grammar still exposes useful nodes for many
    # TypeScript files, but `const GET: RequestHandler = ...` makes the
    # variable name parse as the type. Strip same-line annotations while
    # preserving line numbers so AST row-based callee locations stay valid.
    source
      .gsub(/(\b(?:export\s+)?(?:const|let|var)\s+[A-Za-z_$][\w$]*)\s*:\s*[^=\n]+=/, "\\1 =")
      .gsub(/([,(]\s*[A-Za-z_$][\w$]*)\s*:\s*(?:\{[^}\n]*\}|[^,\)=]+)(?=[,\)])/, "\\1")
      .gsub(/\)\s*:\s*(?:\{[^}\n]*\}|[^=\n]+)=>/, ") =>")
      .gsub(/\)\s*:\s*(?:\{[^}\n]*\}|[^{\n]+){/, ") {")
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

  private def exported_event_handler(root : LibTreeSitter::TSNode,
                                     node : LibTreeSitter::TSNode,
                                     source : String,
                                     event_handler_calls : Set(String),
                                     depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "export_statement"
      if value = Noir::TreeSitter.field(node, "value")
        if handler = event_handler_from_default_value(root, value, source, event_handler_calls)
          return handler
        end
      elsif default_export?(node, source)
        if declaration = Noir::TreeSitter.field(node, "declaration")
          return declaration if handler_node?(declaration)
        end
      elsif local_name = export_clause_local_name(node, source, "default")
        if handler = local_default_event_handler(root, source, local_name, event_handler_calls)
          return handler
        end
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      if handler = exported_event_handler(root, child, source, event_handler_calls, depth + 1)
        return handler
      end
    end
  end

  private def event_handler_from_default_value(root : LibTreeSitter::TSNode,
                                               node : LibTreeSitter::TSNode,
                                               source : String,
                                               event_handler_calls : Set(String)) : LibTreeSitter::TSNode?
    return node if handler_node?(node)

    if Noir::TreeSitter.node_type(node) == "identifier"
      return local_default_event_handler(root, source, Noir::TreeSitter.node_text(node, source), event_handler_calls)
    end

    event_handler_from_wrapper_call(root, node, source, event_handler_calls, 0)
  end

  private def local_default_event_handler(root : LibTreeSitter::TSNode,
                                          source : String,
                                          name : String,
                                          event_handler_calls : Set(String)) : LibTreeSitter::TSNode?
    local_wrapped_event_handler(root, root, source, name, event_handler_calls, 0) ||
      local_callable_handler(root, source, name, 0)
  end

  private def local_wrapped_event_handler(root : LibTreeSitter::TSNode,
                                          node : LibTreeSitter::TSNode,
                                          source : String,
                                          name : String,
                                          event_handler_calls : Set(String),
                                          depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "variable_declarator"
      node_name = Noir::TreeSitter.field(node, "name")
      if node_name && Noir::TreeSitter.node_text(node_name, source) == name
        value = Noir::TreeSitter.field(node, "value")
        return event_handler_from_wrapper_call(root, value, source, event_handler_calls, 0) if value
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      if handler = local_wrapped_event_handler(root, child, source, name, event_handler_calls, depth + 1)
        return handler
      end
    end
  end

  private def event_handler_from_wrapper_call(root : LibTreeSitter::TSNode,
                                              node : LibTreeSitter::TSNode,
                                              source : String,
                                              event_handler_calls : Set(String),
                                              depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if Noir::TreeSitter.node_type(node) == "call_expression"
      name = callee_text(node, source)
      if event_handler_call?(name, event_handler_calls)
        args = arguments_node(node)
        if args
          Noir::TreeSitter.each_named_child(args) do |arg|
            if handler = event_handler_from_arg(root, arg, source, event_handler_calls, depth + 1)
              return handler
            end
          end
        end
      end
    end

    if Noir::TreeSitter.node_type(node) == "parenthesized_expression" || Noir::TreeSitter.node_type(node) == "sequence_expression"
      Noir::TreeSitter.each_named_child(node) do |child|
        if handler = event_handler_from_wrapper_call(root, child, source, event_handler_calls, depth + 1)
          return handler
        end
      end
    end
  end

  private def event_handler_from_arg(root : LibTreeSitter::TSNode,
                                     node : LibTreeSitter::TSNode,
                                     source : String,
                                     event_handler_calls : Set(String),
                                     depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH
    return node if handler_node?(node)

    if Noir::TreeSitter.node_type(node) == "identifier"
      return local_callable_handler(root, source, Noir::TreeSitter.node_text(node, source), 0)
    end

    if handler = event_handler_from_wrapper_call(root, node, source, event_handler_calls, depth + 1)
      return handler
    end

    if Noir::TreeSitter.node_type(node) == "parenthesized_expression" || Noir::TreeSitter.node_type(node) == "sequence_expression"
      Noir::TreeSitter.each_named_child(node) do |child|
        if handler = event_handler_from_arg(root, child, source, event_handler_calls, depth + 1)
          return handler
        end
      end
    end
  end

  private def local_callable_handler(node : LibTreeSitter::TSNode,
                                     source : String,
                                     name : String,
                                     depth : Int32) : LibTreeSitter::TSNode?
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    if handler_node?(node)
      node_name = Noir::TreeSitter.field(node, "name")
      return node if node_name && Noir::TreeSitter.node_text(node_name, source) == name
    end

    if Noir::TreeSitter.node_type(node) == "variable_declarator"
      node_name = Noir::TreeSitter.field(node, "name")
      if node_name && Noir::TreeSitter.node_text(node_name, source) == name
        value = Noir::TreeSitter.field(node, "value")
        return value if value && handler_node?(value)
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      if handler = local_callable_handler(child, source, name, depth + 1)
        return handler
      end
    end
  end

  private def event_handler_call_names(source : String) : Set(String)
    names = EVENT_HANDLER_CALLS.dup

    source.scan(/import\s*\{([^}]+)\}\s*from\s*['"][^'"]+['"]/) do |match|
      match[1].split(",").each do |specifier|
        parts = specifier.strip.split(/\s+as\s+/)
        imported = parts[0]?.try &.strip
        local = parts[1]?.try &.strip
        names.add(local) if imported && local && EVENT_HANDLER_CALLS.includes?(imported)
      end
    end

    loop do
      size = names.size
      alternation = names.map { |name| Regex.escape(name) }.join("|")
      source.scan(/\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:[A-Za-z_$][\w$]*\.)?(?:#{alternation})\b/) do |match|
        names.add(match[1])
      end
      break if names.size == size
    end

    names
  end

  private def event_handler_call?(name : String, event_handler_calls : Set(String)) : Bool
    return true if event_handler_calls.includes?(name)

    if dot = name.rindex('.')
      event_handler_calls.includes?(name[(dot + 1)..-1])
    else
      false
    end
  end

  private def default_export?(node : LibTreeSitter::TSNode, source : String) : Bool
    Noir::TreeSitter.node_text(node, source).matches?(/\Aexport\s+default\b/)
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
                           depth : Int32,
                           definitions : Definitions = Definitions.new)
    return if depth > Noir::TreeSitter::MAX_AST_DEPTH

    skip_function_child : LibTreeSitter::TSNode? = nil
    if Noir::TreeSitter.node_type(node) == "call_expression"
      function = Noir::TreeSitter.field(node, "function") || first_named_child(node)
      name = callee_text(node, source)
      unless name.empty?
        line = Noir::TreeSitter.node_start_row(node) + 1
        if function && Noir::TreeSitter.node_type(function) == "identifier"
          if definitions.has_key?(name) && (def_line = definitions[name])
            line = def_line
          end
        end
        sink << {name, file_path, line}
        skip_function_child = function
      end
    end

    Noir::TreeSitter.each_named_child(node) do |child|
      next if skip_function_child && same_node?(child, skip_function_child)

      walk_callees(child, source, file_path, sink, depth + 1, definitions)
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

  private def route_call_lines(call : LibTreeSitter::TSNode) : Array(Int32)
    lines = [Noir::TreeSitter.node_start_row(call) + 1]
    function = Noir::TreeSitter.field(call, "function") || first_named_child(call)
    if function && Noir::TreeSitter.node_type(function) == "member_expression"
      property = Noir::TreeSitter.field(function, "property")
      if property
        property_line = Noir::TreeSitter.node_start_row(property) + 1
        lines << property_line unless lines.includes?(property_line)
      end
    end

    lines
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
