require "../models/endpoint"
require "./java_route_extractor_ts"
require "./kotlin_route_extractor_ts"
require "./java_parameter_extractor_ts"
require "./kotlin_parameter_extractor_ts"

module Noir
  # Only detached declaration data outlives the route extractor's parse.
  # Resolve cross-file references once every controller has been visited.
  class SpringAnnotationIndex
    record Source, path : String, base : String, project : String, package : String, imports : Array(ImportGraph::ImportRef)
    record Member, name : String, offset : UInt32, rows : Range(Int32, Int32), signature : Array(String), annotations : Array(RouteAnnotation)

    # Declarations have identity in this index. Comparing their method
    # tables on every route would make a controller quadratic in its size.
    class Type
      getter name : String, source : Source, rows : Range(Int32, Int32), parents : Array(String),
        annotations : Array(RouteAnnotation)
      getter? meta : Bool
      getter type_parameters : Array(String)
      getter methods = Hash(String, Array(Member)).new

      def initialize(@name, @source, @rows, @parents, @annotations, @meta, @type_parameters = [] of String)
      end
    end

    record Binding, owner : Type, method : Member?, declaration : Type, evidence : Array(RouteAnnotation)

    @members_by_line = Hash(String, Array({Type, Member})).new
    @offsets = Hash({String, UInt32}, {Type, Member}).new
    @references = [] of String
    @resolved_cursor = 0
    @files = Hash(String, Array(Type)).new
    @types = Hash(String, Array(Type)).new
    @bindings = [] of Binding

    def indexed?(path : String)
      @files.has_key?(path)
    end

    def read(path : String, content : String, base : String, project : String)
      return if indexed?(path)
      if path.ends_with?(".kt")
        TreeSitter.parse_kotlin(content) { |root| add(root, content, path, base, project) }
      elsif path.ends_with?(".java")
        TreeSitter.parse_java(content) { |root| add(root, content, path, base, project) }
      end
    end

    def add(root, content, path, base, project)
      return if indexed?(path)
      kotlin = path.ends_with?(".kt")
      reader = kotlin ? TreeSitterKotlinParameterExtractor : TreeSitterJavaParameterExtractor
      file = Source.new(path, base, project, reader.extract_package_name_from(root, content), reader.extract_imports_from(root, content))
      types = @files[path] = [] of Type
      extractor = kotlin ? TreeSitterKotlinRouteExtractor : TreeSitterJavaRouteExtractor
      extractor.annotation_types(root, content, file, types)
      by_line = @members_by_line[path] = [] of {Type, Member}
      types.each do |type|
        (@types[type.name] ||= [] of Type) << type
        type.parents.each { |parent| @references << parent.split('.').last }
        type.annotations.each { |ann| @references << ann.name.split('.').last }
        type.methods.each_value do |overloads|
          overloads.each do |member|
            @offsets[{path, member.offset}] = {type, member}
            by_line << {type, member}
            member.annotations.each { |ann| @references << ann.name.split('.').last }
          end
        end
      end
      by_line.sort_by! { |(_, member)| member.rows.end }
    end

    # Both locations of an inherited mapping use the same ordered evidence:
    # the concrete override and class precede the declaration of the mapping.
    def bind(location : PathInfo, method_name : String? = nil, implementation : PathInfo? = nil, offset : UInt32? = nil) : PathInfo
      pair = offset ? @offsets[{location.path, offset}]? : member_at(location, method_name)
      return location unless pair
      decl, method = pair
      owner = implementation.try { |impl| type_at(impl) } || decl
      evidence = [] of RouteAnnotation
      @bindings << Binding.new(owner, method, decl, evidence)
      location.route_evidence = evidence
      location
    end

    def direct_annotations(path, method)
      @offsets[{path, LibTreeSitter.ts_node_start_byte(method)}]?.try(&.[1].annotations)
    end

    def empty?
      @bindings.empty?
    end

    def resolve_references(&)
      # Reading one annotation or base can introduce another reference.
      while @resolved_cursor < @references.size
        name = @references[@resolved_cursor]
        @resolved_cursor += 1
        yield name
      end
    end

    def resolve(&)
      resolve_references { |name| yield name }
      @bindings.each { |binding| collect(binding) }
      @bindings.clear
    end

    # Locations supplied by older callers and other analyzers carry no binding.
    def at(location : PathInfo) : Array(RouteAnnotation)?
      pair = member_at(location, nil)
      owner = pair.try(&.[0]) || type_at(location) || return
      method = pair.try(&.[1])
      evidence = [] of RouteAnnotation
      collect(Binding.new(owner, method, owner, evidence), fallback: true)
      evidence
    end

    def each_meta(&)
      @types.each_value do |types|
        types.each { |type| yield type.name, type.annotations if type.meta? }
      end
    end

    private def type_at(location)
      row = location.line || return
      @files[location.path]?.try &.select(&.rows.includes?(row)).min_by?(&.rows.size)
    end

    private def member_at(location, name)
      row = location.line || return
      if name
        type = type_at(location) || return
        method = type.methods[name]?.try &.find(&.rows.includes?(row))
        return {type, method} if method
      elsif pair = @members_by_line[location.path]?.try &.bsearch { |(_, member)| member.rows.end >= row }
        return pair if pair[1].rows.includes?(row)
      end
      nil
    end

    private def collect(binding : Binding, fallback = false)
      owner, method, decl, evidence = binding.owner, binding.method, binding.declaration, binding.evidence
      queue = [{owner, 0, false}]
      seen = Set(Type).new
      until queue.empty?
        type, level, ambiguous = queue.shift
        next unless seen.add?(type)
        inherited = type != owner
        if method
          if type == decl
            expand(method.annotations, type, evidence, inherited ? :inherited_method : :method, level, ambiguous, fallback)
          elsif overloads = type.methods[method.name]?
            exact = overloads.select { |m| !m.signature.includes?("?") && m.signature == method.signature }
            # A generic specialization can change the spelling of an override.
            # Do not borrow a guard from a different concrete overload.
            mixed_language = type.source.path.ends_with?(".kt") != decl.source.path.ends_with?(".kt")
            candidates = exact.empty? ? overloads.select { |m| possible_override?(m.signature, method.signature, mixed_language) } : exact
            candidates.each do |member|
              expand(member.annotations, type, evidence, inherited ? :inherited_method : :method, level, ambiguous || exact.empty?, fallback)
            end
          end
        end
        expand(type.annotations, type, evidence, inherited ? :inherited_class : :class, level + 1, ambiguous, fallback)
        type.parents.each do |parent|
          parents = visible(parent, type, fallback)
          parents.each { |candidate| queue << {candidate, level + 2, ambiguous || parents.size > 1} }
        end
        # The route extractor already followed this implementation to its
        # mapping, even when the two source roots use different import scopes.
        queue << {decl, level + 2, false} if type == owner && decl != owner
      end
      evidence.sort_by!(&.level) if seen.size > 2
    end

    JVM_TYPE_NAMES = {"Integer" => "int", "Character" => "char", "Unit" => "void"}

    private def possible_override?(left, right, mixed_language)
      left.size == right.size && left.zip(right).all? do |a, b|
        next true if a == b || a == "?" || b == "?" || a.ends_with?(".#{b}") || b.ends_with?(".#{a}")
        next false unless mixed_language
        a = a.lchop("java.lang.")
        b = b.lchop("java.lang.")
        JVM_TYPE_NAMES.fetch(a, a).compare(JVM_TYPE_NAMES.fetch(b, b), case_insensitive: true) == 0
      end
    end

    private def visible(name, owner, fallback)
      simple = name.split('.').last
      candidates = @types[simple]?.try(&.select { |t| t.source.base == owner.source.base }) || return [] of Type
      source = owner.source
      explicit = source.imports.find { |imp| !imp.wildcard? && imp.path.ends_with?(".#{name}") }
      qualified = name.includes?('.') ? name : explicit.try(&.path)
      matches = candidates.select do |t|
        qualified ? "#{t.source.package}.#{simple}" == qualified : t.source.package == source.package
      end
      if matches.empty? && !qualified
        matches = candidates.select { |t| source.imports.any? { |imp| imp.wildcard? && imp.path == t.source.package } }
        matches = candidates if fallback && matches.empty? && candidates.size == 1
      end
      local = matches.select { |t| t.source.project == source.project }
      local.empty? ? matches : local
    end

    private def expand(annotations, owner, evidence, origin, level, uncertain, fallback)
      annotations.each do |applied|
        evidence << applied.copy_with(origin: origin, level: level, uncertain: uncertain)
        # Annotation definitions form a graph (including self-annotations).
        # Visit each definition once per application, including diamonds.
        seen = Set(Type).new
        pending = [{owner, applied, uncertain}]
        until pending.empty?
          context, ann, ambiguous = pending.pop
          definitions = visible(ann.name, context, fallback).select(&.meta?)
          definitions.each do |definition|
            next unless seen.add?(definition)
            maybe = ambiguous || definitions.size > 1
            definition.annotations.each do |meta|
              evidence << meta.copy_with(origin: origin, level: level, composed_from: applied.name, uncertain: maybe)
              pending << {definition, meta, maybe}
            end
          end
        end
      end
    end
  end

  # Both route extractors already know where their grammar keeps annotations,
  # declaration names and supertypes. Walk type bodies only, never handler code.
  module SpringAnnotationDeclarations
    def annotation_types(node, content, file, types, owner : SpringAnnotationIndex::Type? = nil) : Nil
      pending = [] of RouteAnnotation
      TreeSitter.each_named_child(node) do |decl|
        case TreeSitter.node_type(decl)
        when "method_declaration", "function_declaration"
          # Older callers can supply a standalone handler snippet.
          type = owner || SpringAnnotationIndex::Type.new("", file, span(decl), [] of String, [] of RouteAnnotation, false)
          add_annotation_method(type, decl, content)
          types << type unless owner
        when "class_declaration", "interface_declaration", "annotation_type_declaration", "object_declaration"
          name, parents, meta, body = annotation_type_parts(decl, content)
          annotations = declaration_annotations(decl, content, file.path)
          annotations.concat(pending)
          type = SpringAnnotationIndex::Type.new(name, file, span(decl), parents, annotations, meta, type_parameters(decl, content))
          types << type
          annotation_types(body, content, file, types, type) if body
        when "prefix_expression"
          # The Kotlin route walker also pairs stray annotations with the
          # following class when the grammar splits its modifiers off.
          pending.concat(TreeSitterKotlinRouteExtractor.prefix_annotations(decl, content, file, types))
          next
        when "line_comment", "multiline_comment"
          next
        end
        pending.clear
      end
    end

    private def span(node)
      (TreeSitter.node_start_row(node) + 1)..(TreeSitter.node_end_row(node) + 1)
    end

    private def add_annotation_method(type, member, content)
      name, signature = annotation_signature(member, content)
      variables = type.type_parameters + type_parameters(member, content)
      signature.map! do |spelling|
        erased = spelling.partition('<')[0].rchop('?')
        variables.includes?(erased) || erased == "..." ? "?" : erased
      end
      methods = type.methods[name] ||= [] of SpringAnnotationIndex::Member
      methods << SpringAnnotationIndex::Member.new(name, LibTreeSitter.ts_node_start_byte(member), span(member), signature, declaration_annotations(member, content, type.source.path))
    end

    private def type_parameters(decl, content)
      names = [] of String
      TreeSitter.each_named_child(decl) do |params|
        next unless TreeSitter.node_type(params) == "type_parameters"
        TreeSitter.each_named_child(params) do |param|
          TreeSitter.each_named_child(param) do |child|
            next unless TreeSitter.node_type(child) == "type_identifier"
            names << TreeSitter.node_text(child, content)
            break
          end
        end
      end
      names
    end

    def declaration_annotations(decl, content, path)
      annotations = [] of RouteAnnotation
      each_annotation(decl, content) do |_, args, row, qualified|
        argument = args.try { |n| TreeSitter.node_text(n, content).lchop('(').rchop(')') }
        annotations << RouteAnnotation.new(qualified, argument, path, row + 1, :method)
      end
      annotations
    end
  end

  module TreeSitterJavaRouteExtractor
    extend SpringAnnotationDeclarations

    private def annotation_type_parts(decl, source)
      parents = [] of String
      TreeSitter.each_named_child(decl) do |clause|
        if TreeSitter.node_type(clause).in?("superclass", "super_interfaces", "extends_interfaces")
          each_supertype_name(clause, source) { |name| parents << name }
        end
      end
      {class_simple_name(decl, source), parents, TreeSitter.node_type(decl) == "annotation_type_declaration", TreeSitter.field(decl, "body")}
    end

    private def annotation_signature(method, source)
      signature = [] of String
      if params = TreeSitter.field(method, "parameters")
        TreeSitter.each_named_child(params) do |param|
          next unless TreeSitter.node_type(param).in?("formal_parameter", "spread_parameter")
          signature << (TreeSitter.field(param, "type").try { |n| TreeSitter.node_text(n, source) } || "...")
        end
      end
      {TreeSitter.field(method, "name").try { |n| TreeSitter.node_text(n, source) } || "", signature}
    end
  end

  module TreeSitterKotlinRouteExtractor
    extend SpringAnnotationDeclarations

    # A bodiless `annotation class A` before a second annotated declaration
    # can be an infix expression surrounded by prefix-expression annotations.
    def prefix_annotations(decl, content, file, types) : Array(RouteAnnotation)
      annotations = [] of RouteAnnotation
      each_stray_annotation(decl, content) do |name, args, row|
        argument = args.try { |n| TreeSitter.node_text(n, content).lchop('(').rchop(')') }
        annotations << RouteAnnotation.new(name, argument, file.path, row + 1, :class)
      end
      node = decl
      while TreeSitter.node_type(node) == "prefix_expression"
        count = LibTreeSitter.ts_node_named_child_count(node)
        return annotations if count == 0
        node = LibTreeSitter.ts_node_named_child(node, count - 1)
      end
      return annotations unless TreeSitter.node_type(node) == "infix_expression" && LibTreeSitter.ts_node_named_child_count(node) == 3
      if class_infix?(node, content)
        name = TreeSitter.node_text(LibTreeSitter.ts_node_named_child(node, 1), content)
        type = SpringAnnotationIndex::Type.new(name, file, span(decl), [] of String, annotations, false)
        body = LibTreeSitter.ts_node_named_child(node, 2)
        add_recovered_methods(type, body, content)
      else
        first = LibTreeSitter.ts_node_named_child(node, 0)
        second = LibTreeSitter.ts_node_named_child(node, 1)
        return annotations unless TreeSitter.node_text(first, content) == "annotation" && TreeSitter.node_text(second, content) == "class"
        name = TreeSitter.node_text(LibTreeSitter.ts_node_named_child(node, 2), content)
        type = SpringAnnotationIndex::Type.new(name, file, span(decl), [] of String, annotations, true)
      end
      types << type
      [] of RouteAnnotation
    end

    private def add_recovered_methods(type, node, content) : Nil
      TreeSitter.each_named_child(node) do |child|
        case TreeSitter.node_type(child)
        when "statements"           then add_recovered_methods(type, child, content)
        when "function_declaration" then add_annotation_method(type, child, content)
        end
      end
    end

    private def annotation_type_parts(decl, source)
      {type_identifier_text(decl, source), implemented_interface_names(decl, source), annotation_class?(decl, source), class_body(decl)}
    end

    private def annotation_signature(method, source)
      signature = [] of String
      TreeSitter.each_named_child(method) do |params|
        next unless TreeSitter.node_type(params) == "function_value_parameters"
        TreeSitter.each_named_child(params) do |param|
          next unless TreeSitter.node_type(param) == "parameter"
          TreeSitter.each_named_child(param) do |child|
            signature << TreeSitter.node_text(child, source) if TreeSitter.node_type(child).ends_with?("type")
          end
        end
      end
      {function_name(method, source), signature}
    end
  end
end
