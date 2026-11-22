module Noir::TreeSitterGoRouteExtractor
  # String fields passed by value to a delegated function, keyed by argument
  # position. Keep the declared fields too: a method call on the parameter
  # may modify it, whereas reading or setting a different field is safe.
  record StructArgument, type : String, fields : Set(String), strings : Hash(String, String)
  alias StructArguments = Hash(Int32, StructArgument)

  # Only a direct, unconditional return to a function in the same package.
  # A second return or a computed argument supplies no field bindings.
  def returned_struct_arguments(body, source, path, structs : Noir::GoStructFields::Index) : StructArguments
    arguments = StructArguments.new
    statements = Noir::TreeSitter.first_named_arg(body)
    return arguments unless statements
    if Noir::TreeSitter.node_type(statements) == "statement_list"
      return arguments unless Noir::TreeSitter.named_arg_count(statements) == 1
      statements = Noir::TreeSitter.first_named_arg(statements)
    elsif Noir::TreeSitter.named_arg_count(body) != 1
      return arguments
    end
    return arguments unless statements && Noir::TreeSitter.node_type(statements) == "return_statement"
    list = Noir::TreeSitter.first_named_arg(statements)
    return arguments unless list && Noir::TreeSitter.named_arg_count(list) == 1
    call = Noir::TreeSitter.first_named_arg(list)
    return arguments unless call && Noir::TreeSitter.node_type(call) == "call_expression"
    function = Noir::TreeSitter.field(call, "function")
    return arguments unless function && Noir::TreeSitter.node_type(function) == "identifier"
    args = Noir::TreeSitter.field(call, "arguments")
    return arguments unless args
    idx = 0
    Noir::TreeSitter.each_named_arg(args) do |arg|
      if Noir::TreeSitter.node_type(arg) == "composite_literal" && (binding = literal_struct_argument(arg, source, path, structs))
        arguments[idx] = binding
      end
      idx += 1
    end
    arguments
  end

  private def literal_struct_argument(arg, source, path, structs) : StructArgument?
    type = Noir::TreeSitter.field(arg, "type")
    return unless type && Noir::TreeSitter.node_type(type) == "type_identifier"
    name = Noir::TreeSitter.node_text(type, source)
    declared = structs.declaration(name, path).try(&.[1]) || return
    # Go initializes an omitted string field to "". A keyed initializer
    # overrides it, including when its expression cannot be read.
    strings = Hash(String, String).new
    declared.each { |f| strings[f.name] = "" if !f.embedded && f.type == "string" }
    values = Noir::TreeSitter.field(arg, "body") || return
    Noir::TreeSitter.each_named_arg(values) do |element|
      return unless Noir::TreeSitter.node_type(element) == "keyed_element"
      key = Noir::TreeSitter.field(element, "key") || return
      field = Noir::TreeSitter.node_text(key, source)
      next unless strings.has_key?(field)
      value = Noir::TreeSitter.field(element, "value").try { |v| Noir::TreeSitter.first_named_arg(v) }
      if value && {"interpreted_string_literal", "raw_string_literal"}.includes?(Noir::TreeSitter.node_type(value))
        strings[field] = decode_string_literal(value, source)
      else
        strings.delete(field)
      end
    end
    StructArgument.new(name, declared.map(&.name).to_set, strings) unless strings.empty?
  end

  # Bind only reads in this function's tree. Route helpers walked using
  # the same seed may have identically named parameters in another scope.
  def bind_struct_arguments(decl, body, source, arguments : StructArguments, values : Hash(String, String)) : Hash(String, String)
    params = Noir::TreeSitter.field(decl, "parameters") || return values
    bound = values.dup
    idx = 0
    Noir::TreeSitter.each_named_arg(params) do |param|
      type = Noir::TreeSitter.field(param, "type")
      next unless type
      names = [] of String
      Noir::TreeSitter.each_named_arg(param) do |child|
        names << Noir::TreeSitter.node_text(child, source) if child.id != type.id && Noir::TreeSitter.node_type(child) == "identifier"
      end
      idx += 1 if names.empty?
      names.each do |name|
        if (arg = arguments[idx]?) && arg.type == Noir::TreeSitter.node_text(type, source)
          bind_struct_reads(body, source, name, arg, bound)
        end
        idx += 1
      end
    end
    bound
  end

  private def bind_struct_reads(body, source, name, arg, values)
    reads = Hash(String, Array(String)).new
    unsafe = Set(String).new
    escapes = false
    Noir::TreeSitter.walk(body) do |node|
      next unless Noir::TreeSitter.node_type(node) == "identifier" && Noir::TreeSitter.node_text(node, source) == name
      # Includes rebindings, shadowing, taking the address and method calls.
      selector = Noir::TreeSitter.parent(node)
      field = if selector && Noir::TreeSitter.node_type(selector) == "selector_expression"
                Noir::TreeSitter.field(selector, "field").try { |f| Noir::TreeSitter.node_text(f, source) }
              end
      unless selector && field && arg.fields.includes?(field)
        escapes = true
        next
      end
      next unless arg.strings.has_key?(field)
      parent = Noir::TreeSitter.parent(selector)
      if parent && Noir::TreeSitter.node_type(parent) == "binary_expression"
        (reads[field] ||= [] of String) << selector_binding_key(selector)
      else
        # A write, an address, or a use we have not proved read-only.
        unsafe << field
      end
    end
    return if escapes
    reads.each do |field, keys|
      next if unsafe.includes?(field)
      values[BOUND_SELECTORS] = ""
      keys.each { |key| values[key] = arg.strings[field] }
    end
  end

  BOUND_SELECTORS = "\u0000selectors"

  private def selector_binding_key(node) : String
    "\u0000#{node.tree.address}:#{node.id.address}"
  end
end
