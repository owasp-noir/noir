require "../ext/tree_sitter/tree_sitter"

module Noir
  # Framework-neutral model of the types a Java file declares: each
  # class / interface with its annotations, supertypes and directly
  # declared methods. Adapters whose routes come from *types* rather
  # than mapping annotations (Spring Data REST repositories, Vaadin
  # `@Route` views, Hilla `@BrowserCallable` services) read this and
  # apply their framework rules; nothing here knows about any of them.
  module TreeSitterJavaTypeModel
    extend self

    struct Annotation
      getter name : String
      # Element values by key; a positional argument is `value`. String
      # literals are decoded, `Foo.class` becomes `Foo`, array
      # initializers fan out, anything else is kept as raw text.
      getter values : Hash(String, Array(String))
      getter line : Int32 # 0-based

      def initialize(@name, @values, @line)
      end

      def string(key = "value") : String?
        @values[key]?.try(&.first?)
      end

      def strings(key = "value") : Array(String)
        @values[key]? || [] of String
      end
    end

    struct MethodParam
      getter name : String
      getter type : String
      getter annotations : Array(Annotation)

      def initialize(@name, @type, @annotations)
      end
    end

    struct Method
      getter name : String
      getter line : Int32 # 0-based
      getter modifiers : Array(String)
      getter annotations : Array(Annotation)
      getter params : Array(MethodParam)

      def initialize(@name, @line, @modifiers, @annotations, @params)
      end
    end

    struct TypeDecl
      getter kind : String # "class" | "interface"
      getter name : String
      getter line : Int32 # 0-based
      getter modifiers : Array(String)
      getter annotations : Array(Annotation)
      # Raw supertype texts, generics kept: `extends` first, then
      # `implements` (classes) or the `extends` list (interfaces).
      getter supertypes : Array(String)
      getter methods : Array(Method)

      def initialize(@kind, @name, @line, @modifiers, @annotations, @supertypes, @methods)
      end

      def annotation(name : String) : Annotation?
        @annotations.find { |ann| ann.name == name }
      end
    end

    def extract(source : String) : Array(TypeDecl)
      types = [] of TypeDecl
      Noir::TreeSitter.parse_java(source) { |root| types = extract_from(root, source) }
      types
    end

    def extract_from(root : LibTreeSitter::TSNode, source : String) : Array(TypeDecl)
      types = [] of TypeDecl
      Noir::TreeSitter.walk(root) do |node|
        kind = case Noir::TreeSitter.node_type(node)
               when "class_declaration"     then "class"
               when "interface_declaration" then "interface"
               end
        next unless kind
        next unless name_node = Noir::TreeSitter.field(node, "name")

        modifiers, annotations = modifiers_of(node, source)
        types << TypeDecl.new(kind, Noir::TreeSitter.node_text(name_node, source),
          Noir::TreeSitter.node_start_row(node), modifiers, annotations,
          supertypes_of(node, source), methods_of(node, source))
      end
      types
    end

    # Simple name of a type text: generics, package and leading
    # annotations dropped (`java.util.List<Foo>` -> `List`).
    def simple_type_name(text : String) : String
      base = text.split('<', 2).first.strip
      base = base.split(/\s+/).last? || base
      base.split('.').last
    end

    # Top-level generic arguments of a type text
    # (`Repo<Person, Map<K, V>>` -> `["Person", "Map<K, V>"]`).
    def type_arguments(text : String) : Array(String)
      return [] of String unless open = text.index('<')
      args = [] of String
      depth = 0
      current = String::Builder.new
      text[(open + 1)..].each_char do |char|
        case char
        when '<'
          depth += 1
        when '>'
          if depth == 0
            args << current.to_s.strip
            return args.reject(&.empty?)
          end
          depth -= 1
        when ','
          if depth == 0
            args << current.to_s.strip
            current = String::Builder.new
            next
          end
        end
        current << char
      end
      args.reject(&.empty?)
    end

    private def supertypes_of(decl : LibTreeSitter::TSNode, source : String) : Array(String)
      types = [] of String
      {"superclass", "interfaces"}.each do |field|
        next unless node = Noir::TreeSitter.field(decl, field)
        collect_type_texts(node, source, types)
      end
      # Interfaces carry their `extends` list as an unfielded child.
      Noir::TreeSitter.each_named_child(decl) do |child|
        collect_type_texts(child, source, types) if Noir::TreeSitter.node_type(child) == "extends_interfaces"
      end
      types
    end

    private def collect_type_texts(node : LibTreeSitter::TSNode, source : String, sink : Array(String))
      Noir::TreeSitter.each_named_child(node) do |child|
        if Noir::TreeSitter.node_type(child) == "type_list"
          collect_type_texts(child, source, sink)
        else
          sink << Noir::TreeSitter.node_text(child, source)
        end
      end
    end

    private def methods_of(decl : LibTreeSitter::TSNode, source : String) : Array(Method)
      methods = [] of Method
      return methods unless body = Noir::TreeSitter.field(decl, "body")

      Noir::TreeSitter.each_named_child(body) do |member|
        next unless Noir::TreeSitter.node_type(member) == "method_declaration"
        next unless name_node = Noir::TreeSitter.field(member, "name")

        modifiers, annotations = modifiers_of(member, source)
        methods << Method.new(Noir::TreeSitter.node_text(name_node, source),
          Noir::TreeSitter.node_start_row(name_node), modifiers, annotations, params_of(member, source))
      end
      methods
    end

    private def params_of(method : LibTreeSitter::TSNode, source : String) : Array(MethodParam)
      params = [] of MethodParam
      return params unless list = Noir::TreeSitter.field(method, "parameters")

      Noir::TreeSitter.each_named_child(list) do |param|
        next unless Noir::TreeSitter.node_type(param) == "formal_parameter"
        name_node = Noir::TreeSitter.field(param, "name")
        type_node = Noir::TreeSitter.field(param, "type")
        next unless name_node && type_node

        _, annotations = modifiers_of(param, source)
        params << MethodParam.new(Noir::TreeSitter.node_text(name_node, source),
          Noir::TreeSitter.node_text(type_node, source), annotations)
      end
      params
    end

    # Keyword modifiers (`public`, `static`, ...) and annotations of a
    # declaration. Keywords are anonymous children, so they need the
    # unnamed-child walk; the node holds a handful of children at most.
    private def modifiers_of(decl : LibTreeSitter::TSNode, source : String) : Tuple(Array(String), Array(Annotation))
      keywords = [] of String
      annotations = [] of Annotation
      Noir::TreeSitter.each_named_child(decl) do |child|
        next unless Noir::TreeSitter.node_type(child) == "modifiers"

        LibTreeSitter.ts_node_child_count(child).times do |i|
          item = LibTreeSitter.ts_node_child(child, i.to_u32)
          case type = Noir::TreeSitter.node_type(item)
          when "annotation", "marker_annotation"
            annotations << annotation_of(item, source)
          else
            keywords << type unless LibTreeSitter.ts_node_is_named(item)
          end
        end
      end
      {keywords, annotations}
    end

    private def annotation_of(node : LibTreeSitter::TSNode, source : String) : Annotation
      name = Noir::TreeSitter.field(node, "name").try { |n| Noir::TreeSitter.node_text(n, source).split('.').last } || ""
      values = Hash(String, Array(String)).new
      if args = Noir::TreeSitter.field(node, "arguments")
        Noir::TreeSitter.each_named_child(args) do |arg|
          if Noir::TreeSitter.node_type(arg) == "element_value_pair"
            key = Noir::TreeSitter.field(arg, "key")
            value = Noir::TreeSitter.field(arg, "value")
            values[Noir::TreeSitter.node_text(key, source)] = element_values(value, source) if key && value
          else
            values["value"] = element_values(arg, source)
          end
        end
      end
      Annotation.new(name, values, Noir::TreeSitter.node_start_row(node))
    end

    private def element_values(node : LibTreeSitter::TSNode, source : String) : Array(String)
      case Noir::TreeSitter.node_type(node)
      when "element_value_array_initializer"
        values = [] of String
        Noir::TreeSitter.each_named_child(node) { |item| values.concat(element_values(item, source)) }
        values
      when "string_literal"
        [Noir::TreeSitter.decode_string_literal(node, source)]
      when "class_literal"
        [Noir::TreeSitter.node_text(node, source).rchop(".class").strip]
      else
        [Noir::TreeSitter.node_text(node, source)]
      end
    end
  end
end
