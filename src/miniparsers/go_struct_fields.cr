require "../ext/tree_sitter/tree_sitter"
require "./go_callee_extractor"

# Go struct field tables, for the request-binding readers: the fields a
# `c.Bind(&req)` fills are the tagged fields of `req`'s struct type,
# embedded structs included.
module Noir::GoStructFields
  record Field, name : String, type : String, tag : String, embedded : Bool

  # `type X struct {...}` declarations in `source`: name -> fields.
  def self.collect(source : String) : Hash(String, Array(Field))
    result = Hash(String, Array(Field)).new
    Noir::TreeSitter.parse_go(source) do |root|
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "type_spec"
        name = Noir::TreeSitter.field(node, "name")
        type = Noir::TreeSitter.field(node, "type")
        next unless name && type && Noir::TreeSitter.node_type(type) == "struct_type"
        result.put_if_absent(Noir::TreeSitter.node_text(name, source)) { fields_of(type, source) }
      end
    end
    result
  end

  # The fields of the `struct { ... }` type literal `text`.
  def self.literal(text : String) : Array(Field)
    collect("package p\ntype t #{text}")["t"]? || [] of Field
  end

  # `key`'s name in a field tag (`json:"name,omitempty"` -> "name"); nil
  # when the tag has no such key or names `-` (never bound).
  def self.tag_value(tag : String, key : String) : String?
    tag.scan(/(?:\A|\s)(\w+):"([^"]*)"/) do |m|
      next unless m[1] == key
      name = m[2].split(',').first
      return name.empty? || name == "-" ? nil : name
    end
    nil
  end

  private def self.fields_of(struct_node : LibTreeSitter::TSNode, source : String) : Array(Field)
    fields = [] of Field
    Noir::TreeSitter.each_named_child(struct_node) do |list|
      next unless Noir::TreeSitter.node_type(list) == "field_declaration_list"
      Noir::TreeSitter.each_named_child(list) do |decl|
        next unless Noir::TreeSitter.node_type(decl) == "field_declaration"
        tag = Noir::TreeSitter.field(decl, "tag").try { |t| Noir::TreeSitter.node_text(t, source).lchop('`').rchop('`') } || ""
        type = Noir::TreeSitter.field(decl, "type").try { |t| Noir::TreeSitter.node_text(t, source) } || ""
        names = [] of String
        Noir::TreeSitter.each_named_child(decl) do |child|
          names << Noir::TreeSitter.node_text(child, source) if Noir::TreeSitter.node_type(child) == "field_identifier"
        end
        if names.empty?
          fields << Field.new(type.lchop('*'), type.lchop('*'), tag, true)
        else
          names.each { |name| fields << Field.new(name, type, tag, false) }
        end
      end
    end
    fields
  end

  # Struct tables per package directory, parsed on first lookup.
  class Index
    MAX_EMBED_DEPTH = 4

    @files_by_dir = Hash(String, Array(String)).new
    # dir -> type name -> {declaring file, fields}
    @structs = Hash(String, Hash(String, Tuple(String, Array(Field)))).new
    @imports = Hash(String, Hash(String, String)).new
    @mutex = Mutex.new

    def initialize(@file_contents : Hash(String, String), @import_dirs : Hash(String, String))
      @file_contents.each_key do |path|
        next if path.ends_with?("_test.go")
        (@files_by_dir[File.dirname(path)] ||= [] of String) << path
      end
    end

    # `type_text` (`T`, `*T`, `pkg.T`) as written in the file `path`,
    # resolved to its struct's fields with embedded structs flattened in.
    # Nil when the type is not a struct declared in the scan.
    def resolve(type_text : String, path : String, depth : Int32 = 0) : Array(Field)?
      return if depth > MAX_EMBED_DEPTH
      qualifier, _, name = type_text.strip.lchop('*').rpartition('.')
      return unless name.matches?(/\A[A-Za-z_]\w*\z/)
      dir = File.dirname(path)
      unless qualifier.empty?
        import_path = imports_of(path)[qualifier]? || return
        dir = @import_dirs[import_path]? || return
      end
      decl_path, fields = structs_for(dir)[name]? || return
      flatten(fields, decl_path, depth)
    end

    # Embedded fields replaced by the fields of their struct, resolved from
    # `path`'s package.
    def flatten(fields : Array(Field), path : String, depth : Int32 = 0) : Array(Field)
      fields.flat_map do |field|
        next [field] unless field.embedded && field.tag.empty?
        resolve(field.type, path, depth + 1) || [] of Field
      end
    end

    private def structs_for(dir : String) : Hash(String, Tuple(String, Array(Field)))
      @mutex.synchronize do
        @structs[dir] ||= begin
          table = Hash(String, Tuple(String, Array(Field))).new
          @files_by_dir[dir]?.try &.each do |file|
            content = @file_contents[file]
            next unless content.includes?("struct")
            Noir::GoStructFields.collect(content).each { |name, fields| table.put_if_absent(name) { {file, fields} } }
          end
          table
        end
      end
    end

    private def imports_of(path : String) : Hash(String, String)
      @mutex.synchronize do
        @imports[path] ||= @file_contents[path]?.try { |c| Noir::GoCalleeExtractor.extract_import_aliases(c) } || Hash(String, String).new
      end
    end
  end
end
