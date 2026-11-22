require "./js_ts_ast_helpers"

module Noir
  # Possible arguments of a registry dispatch such as callbacks[key](app, mounts[key]).
  # A configurable map can still have source-backed defaults: for example,
  # keys.forEach(k => { if (!(k in mounts)) mounts[k] = k }). These values
  # describe the default placement of each registrar.
  module JSRegistrarDefaults
    extend self
    include JSTSAstHelpers

    alias Node = LibTreeSitter::TSNode
    alias TS = TreeSitter
    record Argument, function : String, import_path : String?, position : Int32, value : String

    private def children(node : Node?) : Array(Node)
      result = [] of Node
      TS.each_named_child(node) { |child| result << child unless TS.node_type(child) == "comment" } if node
      result
    end

    private def field_text(node, key, source) : String
      TS.field(node, key).try { |child| TS.node_text(child, source) } || ""
    end

    private def parameters(node, source) : Array(String)
      if param = TS.field(node, "parameter")
        return [TS.node_text(param, source)]
      end
      children(TS.field(node, "parameters")).map { |arg| TS.node_text(arg, source) }
    end

    private def member_call(node, source, methods) : {Node, Node}?
      return unless TS.node_type(node) == "call_expression"
      fn = TS.field(node, "function") || return
      return unless TS.node_type(fn) == "member_expression" && methods.includes?(field_text(fn, "property", source))
      owner = TS.field(fn, "object") || return
      arg = children(TS.field(node, "arguments")).first? || return
      {owner, arg}
    end

    # Only local, preceding declarations visible to this use. Module-level
    # constants can supply the keys or the registry used inside a function.
    private def declaration(node, name, source) : Node?
      child = node
      while scope = TS.parent(child)
        type = TS.node_type(scope)
        return if type.in?("function_declaration", "function_expression", "arrow_function") && parameters(scope, source).includes?(name)
        if type.in?("statement_block", "program")
          children(scope).each do |statement|
            break if LibTreeSitter.ts_node_start_byte(statement) >= LibTreeSitter.ts_node_start_byte(child)
            next unless TS.node_type(statement) == "lexical_declaration"
            children(statement).each do |decl|
              return TS.field(decl, "value") if field_text(decl, "name", source) == name
            end
          end
        end
        child = scope
      end
      nil
    end

    # Stay inside this function. Nested closures have their own parameters.
    private def walk_scope(node : Node, &block : Node ->)
      return if TS.node_type(node).in?("function_declaration", "function_expression", "arrow_function")
      yield node
      TS.each_named_child(node) { |child| walk_scope(child, &block) }
    end

    def extract(source : String, path : String) : Array(Argument)
      found = [] of Argument
      return found unless source.includes?("Object.keys") && source.includes?("forEach")
      TS.parse_js_family(source, path) do |root|
        functions = {} of String => Node
        children(root).each do |decl|
          functions[field_text(decl, "name", source)] = decl if TS.node_type(decl) == "function_declaration"
        end
        TS.walk(root) do |call|
          owner, callback = member_call(call, source, {"forEach"}) || next
          array = declaration(call, TS.node_text(owner, source), source) || next
          next unless TS.node_type(array) == "array"
          keys = children(array)
          next unless 0 < keys.size <= 64 && keys.all? { |k| TS.node_type(k) == "string" }
          key = parameters(callback, source).first? || next
          block = TS.field(callback, "body") || next
          walk_scope(block) do |assignment|
            next unless TS.node_type(assignment) == "assignment_expression"
            left = TS.field(assignment, "left") || next
            next unless TS.node_type(left) == "subscript_expression" && field_text(left, "index", source) == key
            map = field_text(left, "object", source)
            right = TS.field(assignment, "right") || next
            identity = TS.node_type(right) == "identifier" && TS.node_text(right, source) == key
            next unless identity || TS.node_type(right) == "string"
            defaults = keys.to_h { |k| {decode_string(k, source), decode_string(identity ? k : right, source)} }
            scope = TS.parent(call)
            while scope && !TS.node_type(scope).in?("statement_block", "program")
              scope = TS.parent(scope)
            end
            trace(scope, map, defaults, functions, source, found, Set({UInt32, String}).new, LibTreeSitter.ts_node_end_byte(call)) if scope
          end
        end
      end
      found.uniq
    end

    private def trace(scope, map, defaults, functions, source, found, visited, start_byte = 0_u32)
      return if visited.size >= 32 || !visited.add?({LibTreeSitter.ts_node_start_byte(scope), map})
      walk_scope(scope) do |call|
        next if LibTreeSitter.ts_node_start_byte(call) < start_byte
        next unless TS.node_type(call) == "call_expression"
        if iteration = member_call(call, source, {"map", "forEach"})
          owner, callback = iteration
          if TS.node_type(owner) == "call_expression" && field_text(owner, "function", source) == "Object.keys" &&
             children(TS.field(owner, "arguments")).first?.try { |arg| TS.node_text(arg, source) } == map
            read_dispatch(callback, map, defaults, source, found)
          end
        end
        target = functions[field_text(call, "function", source)]? || next
        body = TS.field(target, "body") || next
        params = parameters(target, source)
        children(TS.field(call, "arguments")).each_with_index do |arg, idx|
          if TS.node_text(arg, source) == map && (param = params[idx]?)
            trace(body, param, defaults, functions, source, found, visited)
          end
        end
      end
    end

    # Keep key and value aliases separate: callbacks[key](app, values[key])
    # can dispatch to a different function for every key of the same map.
    private def read_dispatch(callback, map, defaults, source, found)
      key = parameters(callback, source).first? || return
      body = TS.field(callback, "body") || return
      keys = Set{key}
      values = Set(String).new
      statements = TS.node_type(body) == "statement_block" ? children(body) : [body]
      statements.each do |statement|
        steps = TS.node_type(statement).in?("lexical_declaration", "expression_statement") ? children(statement) : [statement]
        steps.each do |step|
          case TS.node_type(step)
          when "variable_declarator", "assignment_expression"
            local = TS.node_type(step) == "variable_declarator"
            name = field_text(step, local ? "name" : "left", source)
            rhs = TS.field(step, local ? "value" : "right") || next
            is_key = keys.includes?(TS.node_text(rhs, source))
            is_value = map_value?(rhs, source, map, keys, values)
            keys.delete(name)
            values.delete(name)
            keys << name if is_key
            values << name if is_value
          when "call_expression"
            fn = TS.field(step, "function") || next
            next unless TS.node_type(fn) == "subscript_expression" && keys.includes?(field_text(fn, "index", source))
            registry = field_text(fn, "object", source)
            imports = registry_imports(step, registry, source)
            children(TS.field(step, "arguments")).each_with_index do |arg, idx|
              next unless map_value?(arg, source, map, keys, values)
              defaults.each { |k, v| found << Argument.new("#{registry}.#{k}", imports[k]?, idx, v) }
            end
          end
        end
      end
    end

    private def map_value?(node, source, map, keys, values) : Bool
      values.includes?(TS.node_text(node, source)) || (TS.node_type(node) == "subscript_expression" &&
        field_text(node, "object", source) == map && keys.includes?(field_text(node, "index", source)))
    end

    private def registry_imports(call, registry, source) : Hash(String, String)
      imports = {} of String => String
      object = declaration(call, registry, source)
      return imports unless object && TS.node_type(object) == "object"
      children(object).each do |pair|
        key = TS.field(pair, "key") || next
        value = TS.field(pair, "value") || next
        next unless TS.node_type(value) == "call_expression" && field_text(value, "function", source) == "require"
        spec = children(TS.field(value, "arguments")).first? || next
        next unless TS.node_type(spec) == "string"
        imports[decode_string(key, source)] = decode_string(spec, source) if TS.node_type(key) == "string"
        imports[TS.node_text(key, source)] = decode_string(spec, source) if TS.node_type(key) == "property_identifier"
      end
      imports
    end
  end
end
