require "../ext/tree_sitter/tree_sitter"

module Noir
  # A source-only description of request types and the modules they depend on.
  # AST nodes stay inside the parse block. References retain the declaring
  # module's local spelling until the caller resolves its imports.
  class TsDtoModule
    alias Node = LibTreeSitter::TSNode
    record Base, name : String, pick : Array(String)? = nil, omit : Array(String) = [] of String
    # A wrapper must return its first argument's schema, or z.object of
    # that argument when the caller passed a raw shape.
    record Wrapper, name : String, raw_shape : Bool
    record Shape, fields = [] of String, bases = [] of Base, wrappers = [] of Wrapper do
      def +(other : Shape) : Shape
        Shape.new(fields | other.fields, bases | other.bases, wrappers | other.wrappers)
      end

      def select_keys(keys : Array(String), pick : Bool) : Shape
        filtered = bases.map do |base|
          if pick
            Base.new(base.name, base.pick.try { |previous| previous & keys } || keys, base.omit)
          else
            Base.new(base.name, base.pick, base.omit | keys)
          end
        end
        Shape.new(pick ? fields & keys : fields - keys, filtered, wrappers)
      end
    end

    record Binding, name : String, source : String? = nil
    getter declarations = {} of String => Shape
    getter imports = {} of String => Binding
    getter exports = {} of String => Binding
    getter wrappers = {} of String => Bool
    getter stars = [] of String

    def self.parse(source : String, path : String) : self
      table = new
      typescript = path.ends_with?(".ts") || path.ends_with?(".cts") || path.ends_with?(".mts")
      TreeSitter.parse(source, typescript ? LibTreeSitter.tree_sitter_typescript : LibTreeSitter.tree_sitter_tsx) do |root|
        Reader.new(source, table).read(root)
      end
      table
    end

    private class Reader
      # These operations preserve the keys of the input object, including
      # pipe, whose right-hand schema describes the *output* of the first.
      INPUT_KEYS = %w[meta describe refine superRefine pipe transform default optional nullable partial required strict passthrough strip readonly]

      def initialize(@source : String, @table : TsDtoModule)
        @literal_keys = {} of String => String
      end

      private def text(node : Node) : String
        TreeSitter.node_text(node, @source)
      end

      private def field_text(node : Node, key : String) : String?
        TreeSitter.field(node, key).try { |child| text(child) }
      end

      def read(root : Node) : Nil
        values = {} of String => Node
        TreeSitter.each_named_arg(root) do |statement|
          case TreeSitter.node_type(statement)
          when "import_statement"
            read_import(statement)
            next
          when "export_statement"
            read_exports(statement)
            node = TreeSitter.field(statement, "declaration") || next
          else
            node = statement
          end
          exported = TreeSitter.node_type(statement) == "export_statement"
          name = field_text(node, "name")
          if name && exported
            key = child_token?(statement, "default") ? "default" : name
            @table.exports[key] = Binding.new(name)
          end
          case TreeSitter.node_type(node)
          when "enum_declaration"
            enum_keys(node, name) if name
          when "class_declaration", "abstract_class_declaration", "interface_declaration"
            class_shape(node).try { |shape| @table.declarations[name] = shape } if name
          when "type_alias_declaration"
            if name && (value = TreeSitter.field(node, "value"))
              type_shape(value).try { |shape| @table.declarations[name] = shape }
            end
          when "function_declaration"
            record_wrapper(name, node) if name
          when "lexical_declaration", "variable_declaration"
            TreeSitter.each_named_arg(node) do |decl|
              local = field_text(decl, "name") || next
              value = TreeSitter.field(decl, "value") || next
              values[local] = value
              @table.exports[local] = Binding.new(local) if exported
              record_wrapper(local, value) if TreeSitter.node_type(value) == "arrow_function"
            end
          end
        end
        values.each { |name, value| expression(value).try { |shape| @table.declarations[name] = shape } }
      end

      private def read_import(statement : Node)
        from = TreeSitter.field(statement, "source") || return
        source = TreeSitter.decode_string_literal(from, @source)
        TreeSitter.each_named_arg(statement) do |clause|
          next unless TreeSitter.node_type(clause) == "import_clause"
          TreeSitter.each_named_arg(clause) do |part|
            case TreeSitter.node_type(part)
            when "identifier"
              @table.imports[text(part)] = Binding.new("default", source)
            when "namespace_import"
              TreeSitter.first_named_arg(part).try { |local| @table.imports[text(local)] = Binding.new("*", source) }
            when "named_imports"
              bindings(part, source, @table.imports)
            end
          end
        end
      end

      private def read_exports(statement : Node)
        if value = TreeSitter.field(statement, "value")
          @table.exports["default"] = Binding.new(text(value)) if TreeSitter.node_type(value) == "identifier"
        end
        source = TreeSitter.field(statement, "source").try { |from| TreeSitter.decode_string_literal(from, @source) }
        TreeSitter.each_named_arg(statement) do |clause|
          if TreeSitter.node_type(clause) == "export_clause"
            bindings(clause, source, @table.exports)
            return
          end
        end
        @table.stars << source if source && text(statement).matches?(/\bexport\s+(?:type\s+)?\*\s+from\b/)
      end

      private def bindings(clause : Node, source : String?, into : Hash(String, Binding))
        TreeSitter.each_named_arg(clause) do |spec|
          name = field_text(spec, "name") || next
          into[field_text(spec, "alias") || name] = Binding.new(name, source)
        end
      end

      private def enum_keys(node : Node, name : String)
        body = TreeSitter.field(node, "body") || return
        TreeSitter.each_named_arg(body) do |member|
          key = field_text(member, "name") || next
          value = TreeSitter.field(member, "value") || next
          @literal_keys["#{name}.#{key}"] = TreeSitter.decode_string_literal(value, @source) if TreeSitter.node_type(value) == "string"
        end
      end

      private def class_shape(node : Node) : Shape?
        body = TreeSitter.field(node, "body") || return
        shape = member_shape(body) || return
        TreeSitter.each_named_arg(node) do |heritage|
          case TreeSitter.node_type(heritage)
          when "class_heritage"
            TreeSitter.each_named_arg(heritage) do |clause|
              next unless TreeSitter.node_type(clause) == "extends_clause"
              base = TreeSitter.field(clause, "value") || return
              shape += expression(base) || return
            end
          when "extends_type_clause"
            TreeSitter.each_named_arg(heritage) { |base| shape += expression(base) || return }
          end
        end
        shape
      end

      private def type_shape(node : Node) : Shape?
        case TreeSitter.node_type(node)
        when "object_type"
          member_shape(node)
        when "type_identifier", "nested_type_identifier", "generic_type"
          expression(node)
        end
      end

      private def member_shape(body : Node) : Shape?
        shape = Shape.new
        TreeSitter.each_named_arg(body) do |member|
          case TreeSitter.node_type(member)
          when "ERROR", "index_signature"
            return # A dictionary can receive arbitrary keys.
          when "method_definition"
            constructor_fields(member, shape.fields) if field_text(member, "name") == "constructor"
            next
          when "public_field_definition", "property_signature", "abstract_property_signature"
            # Data property.
          else
            next
          end
          next if private_or_static?(member)
          type = TreeSitter.field(member, "type").try { |ann| TreeSitter.first_named_arg(ann) }
          value = TreeSitter.field(member, "value")
          next if type && TreeSitter.node_type(type) == "function_type"
          next if value && {"arrow_function", "function_expression"}.includes?(TreeSitter.node_type(value))
          key = TreeSitter.field(member, "name") || next
          next if TreeSitter.node_type(key) == "private_property_identifier"
          shape.fields << (property_name(key) || return)
        end
        shape
      end

      private def constructor_fields(method : Node, fields : Array(String))
        params = TreeSitter.field(method, "parameters") || return
        TreeSitter.each_named_arg(params) do |param|
          next unless child_token?(param, "accessibility_modifier") || child_token?(param, "readonly")
          next if private_or_static?(param)
          pattern = TreeSitter.field(param, "pattern") || next
          fields << text(pattern) if TreeSitter.node_type(pattern) == "identifier"
        end
      end

      private def child_token?(node : Node, kind : String) : Bool
        LibTreeSitter.ts_node_child_count(node).times do |i|
          return true if TreeSitter.node_type(LibTreeSitter.ts_node_child(node, i)) == kind
        end
        false
      end

      private def private_or_static?(member : Node) : Bool
        LibTreeSitter.ts_node_child_count(member).times do |i|
          child = LibTreeSitter.ts_node_child(member, i)
          return true if TreeSitter.node_type(child) == "static"
          return true if TreeSitter.node_type(child) == "accessibility_modifier" && text(child) != "public"
        end
        false
      end

      private def property_name(key : Node) : String?
        case TreeSitter.node_type(key)
        when "property_identifier", "shorthand_property_identifier", "number"
          text(key)
        when "string"
          TreeSitter.decode_string_literal(key, @source)
        when "computed_property_name"
          TreeSitter.first_named_arg(key).try { |expr| @literal_keys[text(expr)]? }
        end
      end

      private def object_keys(obj : Node) : Array(String)?
        return unless TreeSitter.node_type(obj) == "object"
        keys = [] of String
        TreeSitter.each_named_arg(obj) do |pair|
          key = TreeSitter.field(pair, "key") || pair
          keys << (property_name(key) || return)
        end
        keys
      end

      # A local validator wrapper is transparent only when its sole result
      # is its schema parameter (possibly refined). Arbitrary calls can
      # replace the entire shape.
      private def record_wrapper(local : String, fn : Node) : Nil
        params = TreeSitter.field(fn, "parameters") || return
        param = TreeSitter.first_named_arg(params) || return
        name = field_text(param, "pattern") || return
        body = TreeSitter.field(fn, "body") || return
        result = body
        if TreeSitter.node_type(body) == "statement_block"
          found = nil.as(Node?)
          TreeSitter.each_named_arg(body) do |stmt|
            case TreeSitter.node_type(stmt)
            when "lexical_declaration" then next
            when "return_statement"
              return if found
              found = TreeSitter.first_named_arg(stmt)
            else return
            end
          end
          result = found || return
        end
        raw_shape = false
        while TreeSitter.node_type(result) == "call_expression"
          callee = TreeSitter.field(result, "function") || return
          receiver = TreeSitter.field(callee, "object") || return
          property = field_text(callee, "property")
          if property == "object" && text(receiver) == "z"
            args = TreeSitter.field(result, "arguments") || return
            result = TreeSitter.first_named_arg(args) || return
            raw_shape = true
            break
          end
          return unless INPUT_KEYS.includes?(property)
          result = receiver
        end
        @table.wrappers[local] = raw_shape if TreeSitter.node_type(result) == "identifier" && text(result) == name
      end

      private def expression(node : Node, depth : Int32 = 0) : Shape?
        return if depth > 32
        node = TreeSitter.unwrap_expression(node)
        case TreeSitter.node_type(node)
        when "identifier", "type_identifier", "nested_type_identifier", "member_expression"
          Shape.new(bases: [Base.new(text(node))])
        when "generic_type"
          TreeSitter.field(node, "name").try { |name| expression(name, depth + 1) }
        when "call_expression"
          callee = TreeSitter.field(node, "function") || return
          args = [] of Node
          TreeSitter.field(node, "arguments").try { |list| TreeSitter.each_named_arg(list) { |arg| args << arg } }
          if receiver = TreeSitter.field(callee, "object")
            property = field_text(callee, "property") || return
            return schema_method(receiver, property, args.first?, depth + 1)
          end
          name = text(callee)
          binding = @table.imports[name]?
          if binding && {"@nestjs/mapped-types", "@nestjs/swagger", "@nestjs/graphql", "nestjs-zod"}.includes?(binding.source)
            name = binding.name
          end
          arg = args.first? || return
          case name
          when "IntersectionType"
            shape = Shape.new
            args.each { |base| shape += expression(base, depth + 1) || return }
            shape
          when "PickType", "OmitType"
            array = args[1]?.try { |keys| TreeSitter.unwrap_expression(keys) } || return
            return unless TreeSitter.node_type(array) == "array"
            keys = [] of String
            TreeSitter.each_named_arg(array) do |key|
              return unless TreeSitter.node_type(key) == "string"
              keys << TreeSitter.decode_string_literal(key, @source)
            end
            expression(arg, depth + 1).try &.select_keys(keys, name == "PickType")
          when "PartialType", "RequiredType", "createZodDto"
            expression(arg, depth + 1)
          else
            raw_shape = TreeSitter.node_type(arg) == "object"
            shape = raw_shape ? object_keys(arg).try { |keys| Shape.new(keys) } : expression(arg, depth + 1)
            shape.try { |input| input + Shape.new(wrappers: [Wrapper.new(name, raw_shape)]) }
          end
        end
      end

      private def schema_method(receiver : Node, property : String, arg : Node?, depth : Int32) : Shape?
        case property
        when "object", "strictObject", "looseObject"
          return unless text(receiver) == "z" && arg
          object_keys(arg).try { |keys| Shape.new(keys) }
        when "class"
          # zod-class declares class members in the object passed to Z.class.
          return unless text(receiver) == "Z" && arg
          object_keys(arg).try { |keys| Shape.new(keys) }
        when "extend", "pick", "omit"
          keys = arg.try { |obj| object_keys(obj) } || return
          base = expression(receiver, depth) || return
          property == "extend" ? base + Shape.new(keys) : base.select_keys(keys, property == "pick")
        else
          expression(receiver, depth) if INPUT_KEYS.includes?(property)
        end
      end
    end
  end
end
