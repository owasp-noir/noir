require "../ext/tree_sitter/tree_sitter"

module Noir
  # The request reads reachable in a Pages Router default handler. Keep the
  # surrounding source for shared reads, aliases and helpers. Only edit spans
  # whose binding or control flow can be determined from the module.
  class JSRequestMethodScope
    alias Node = LibTreeSitter::TSNode
    alias TS = Noir::TreeSitter

    record Edit, start : Int32, finish : Int32, replacement : String

    @edits : Hash(String, Array(Edit))

    def initialize(@source : String, @methods : Array(String))
      @edits = @methods.to_h { |method| {method, [] of Edit} }
      @method_refs = Set(String).new
    end

    def sources(path : String) : Hash(String, String)
      bracket_keys = @source.matches?(/\b(?:headers|cookies)\s*(?:\?\.)?\s*\[\s*[A-Za-z_$]/)
      methods_checked = @source.includes?("method")
      return @methods.to_h { |method| {method, @source} } unless bracket_keys || methods_checked

      TS.parse_js_family(@source, path) do |root|
        unless TS.node_has_error?(root)
          resolve_bracket_keys(root) if bracket_keys
          TS.each_named_child(root) { |node| read_default(node) } if methods_checked
        end
      end
      @edits.transform_values { |edits| apply(edits) }
    rescue
      @methods.to_h { |method| {method, @source} }
    end

    private def text(node : Node) : String
      TS.node_text(node, @source)
    end

    private def edit(node : Node, replacement : String = " ") : Edit
      Edit.new(LibTreeSitter.ts_node_start_byte(node).to_i, LibTreeSitter.ts_node_end_byte(node).to_i, replacement)
    end

    private def apply(edits : Array(Edit)) : String
      return @source if edits.empty?
      String.build do |io|
        pos = 0
        edits.sort_by!(&.start).each do |change|
          next if change.start < pos # An enclosing unreachable branch was already removed.
          io << @source.byte_slice(pos, change.start - pos) << change.replacement
          pos = change.finish
        end
        io << @source.byte_slice(pos..)
      end
    end

    # Resolve a module-level const only when every other occurrence of its
    # identifier is a bracket index. A parameter, local binding or pattern
    # with the same name leaves the unresolved-key evidence intact.
    private def resolve_bracket_keys(root : Node) : Nil
      literals = {} of String => Tuple(Int32, String)
      TS.each_named_child(root) do |statement|
        declaration = TS.field(statement, "declaration") || statement
        next unless TS.node_type(declaration) == "lexical_declaration" && TS.field(declaration, "kind").try { |kind| text(kind) == "const" }
        TS.each_named_child(declaration) do |binding|
          name = TS.field(binding, "name") || next
          value = TS.field(binding, "value").try { |expr| TS.unwrap_expression(expr) } || next
          next unless TS.node_type(name) == "identifier" && TS.node_type(value) == "string"
          # The downstream reader accepts plain quoted wire keys.
          literal = text(value)
          next unless literal.matches?(/\A['"][^'"\\\s]+['"]\z/)
          literals[text(name)] = {LibTreeSitter.ts_node_start_byte(name).to_i, literal}
        end
      end
      return if literals.empty?
      uses = [] of Tuple(String, Node)
      TS.walk(root) do |node|
        next unless TS.node_type(node).in?("identifier", "shorthand_property_identifier_pattern", "type_identifier")
        name = text(node)
        literal = literals[name]? || next
        next if LibTreeSitter.ts_node_start_byte(node).to_i == literal[0]
        parent = TS.parent(node)
        if parent && TS.node_type(parent) == "subscript_expression" && TS.field(parent, "index").try(&.id) == node.id
          object = TS.field(parent, "object") || next
          property = TS.field(object, "property")
          uses << {name, node} if property && text(property).in?("headers", "cookies")
        else
          literals.delete(name)
        end
      end
      uses.each do |name, node|
        next unless literal = literals[name]?
        change = edit(node, literal[1])
        @edits.each_value { |edits| edits << change }
      end
    end

    private def read_default(statement : Node) : Nil
      return unless TS.node_type(statement) == "export_statement" && text(statement).matches?(/\Aexport\s+default\b/)
      fn = TS.field(statement, "declaration") || TS.field(statement, "value") || return
      return unless TS.node_type(fn).in?("function_declaration", "function_expression", "arrow_function")
      params = TS.field(fn, "parameters")
      first = params.try { |list| TS.first_named_arg(list) } || TS.field(fn, "parameter") || return
      first = TS.field(first, "pattern") || first
      return unless TS.node_type(first) == "identifier"
      request = text(first)
      body = TS.field(fn, "body") || return
      return if request_reassigned?(body, request)
      @method_refs << "#{request}.method"
      # A direct statement in this function sees its first argument and
      # preceding const declarations. Nested scopes may rebind either.
      TS.each_named_child(body) do |node|
        case TS.node_type(node)
        when "lexical_declaration"
          method_aliases(node, request)
        when "if_statement"
          @methods.each { |method| read_if(node, method) }
        when "switch_statement"
          read_switch(node)
        end
      end
    end

    # Reassigning the request or overriding its method makes a later
    # comparison a test of a local value, not of the incoming HTTP verb.
    private def request_reassigned?(body : Node, request : String) : Bool
      reassigned = false
      TS.walk(body) do |node|
        next unless TS.node_type(node).in?("assignment_expression", "augmented_assignment_expression", "update_expression")
        target = TS.field(node, "left") || TS.field(node, "argument") || next
        case TS.node_type(target)
        when "identifier"
          reassigned = true if text(target) == request
        when "member_expression"
          reassigned = true if TS.field(target, "property").try { |key| text(key) == "method" }
        when "subscript_expression"
          reassigned = true if TS.field(target, "object").try { |obj| text(obj) == request }
        when "object_pattern", "array_pattern"
          reassigned = true if text(target).includes?(request)
        end
      end
      reassigned
    end

    private def method_aliases(node : Node, request : String) : Nil
      return unless TS.field(node, "kind").try { |kind| text(kind) == "const" }
      TS.each_named_child(node) do |binding|
        name = TS.field(binding, "name") || next
        value = TS.field(binding, "value") || next
        if text(value) == "#{request}.method" && TS.node_type(name) == "identifier"
          @method_refs << text(name)
        elsif text(value) == request && TS.node_type(name) == "object_pattern"
          TS.each_named_child(name) do |key|
            @method_refs << "method" if TS.node_type(key) == "shorthand_property_identifier_pattern" && text(key) == "method"
          end
        end
      end
    end

    private def compared_method(node : Node) : String?
      return unless TS.node_type(node) == "binary_expression"
      op = TS.field(node, "operator") || return
      return unless text(op).in?("===", "==")
      left = TS.field(node, "left") || return
      right = TS.field(node, "right") || return
      return unless @method_refs.includes?(text(left)) && TS.node_type(right) == "string"
      TS.decode_string_literal(right, @source)
    end

    private def read_if(node : Node, method : String) : Nil
      loop do
        cond = TS.field(node, "condition").try { |expr| TS.unwrap_expression(expr) } || return
        branch = TS.field(node, "consequence") || return
        alternative = TS.field(node, "alternative")
        if verb = compared_method(cond)
          if verb == method
            @edits[method] << edit(alternative) if alternative
            return
          end
          @edits[method] << edit(branch)
        elsif TS.field(cond, "operator").try { |op| text(op) == "||" }
          left = TS.field(cond, "left") || return
          if compared_method(left) == method
            right = TS.field(cond, "right") || return
            @edits[method] << edit(right)
            @edits[method] << edit(alternative) if alternative
            return
          end
        end
        node = alternative.try { |clause| TS.first_named_arg(clause) } || return
        return unless TS.node_type(node) == "if_statement"
      end
    end

    private def read_switch(node : Node) : Nil
      value = TS.field(node, "value").try { |expr| TS.unwrap_expression(expr) } || return
      return unless @method_refs.includes?(text(value))
      body = TS.field(node, "body") || return
      cases = [] of Tuple(Node, String?, Bool)
      TS.each_named_arg(body) do |arm|
        label = TS.field(arm, "value")
        return if label && TS.node_type(label) != "string"
        last = nil.as(Node?)
        TS.each_named_arg(arm) do |child|
          # A function declared directly in one arm can be called by another.
          return if TS.node_type(child).in?("function_declaration", "generator_function_declaration")
          last = child
        end
        if last && TS.node_type(last) == "statement_block"
          TS.each_named_arg(last) { |child| last = child }
        end
        stops = last.try { |tail| TS.node_type(tail).in?("return_statement", "throw_statement", "break_statement") }
        cases << {arm, label.try { |key| TS.decode_string_literal(key, @source) }, !!stops}
      end
      @methods.each do |method|
        entry = cases.index { |(_, label, _)| label == method } || cases.index { |(_, label, _)| label.nil? }
        reachable = false
        cases.each_with_index do |(arm, _, stops), i|
          reachable ||= i == entry
          @edits[method] << edit(arm) unless reachable
          reachable = false if stops
        end
      end
    end
  end
end
