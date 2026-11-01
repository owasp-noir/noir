require "./csharp_decl_parser"

module Noir
  # One top-level `class` declaration, located by line range inside the file
  # the extractor was handed. The range (0-based, inclusive) spans the leading
  # attribute list through the closing brace, so a caller can slice the
  # lexer's own `code_lines`/`masked_lines` instead of re-lexing a substring.
  # `decl` is the parsed declaration: attributes, base list and members as
  # structured nodes.
  record CSharpType,
    name : String,
    base_name : String?,
    attributes : Array(String),
    modifiers : Array(String),
    generic : Bool,
    start_line : Int32,
    end_line : Int32,
    header : String, # masked attribute list + declaration, up to the `{`
    decl : CSharpDecl::TypeDecl

  module CSharpTypeExtractor
    # The classes declared directly in a namespace (or the global one); a
    # type nested in another is not listed.
    def self.extract(lexer : CSharpLexer) : Array(CSharpType)
      CSharpDeclParser.parse(lexer).top_types.compact_map do |decl|
        next unless decl.kind == "class" && decl.open
        CSharpType.new(
          decl.name, decl.base_name, decl.attributes.map(&.name), decl.modifiers,
          !decl.type_params.nil?, decl.start_line, decl.end_line, decl.header, decl
        )
      end
    end
  end
end
