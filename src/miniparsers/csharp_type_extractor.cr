require "../minilexers/csharp_lexer"

module Noir
  record CSharpType,
    name : String,
    base_name : String?,
    attributes : Array(String),
    modifiers : Array(String),
    generic : Bool,
    content : String,
    line_offset : Int32

  module CSharpTypeExtractor
    HEADER = /((?:\[[^\]]*\]\s*)*)((?:(?:public|internal|private|protected|abstract|sealed|static|partial|new)\s+)*)(class|struct|interface|record)\s+(\w+)([^{};]*)\{/m

    def self.extract(content : String) : Array(CSharpType)
      lexer = CSharpLexer.new(content)
      source = lexer.code_source
      masked = lexer.masked.join
      types = [] of CSharpType
      enclosing_end = -1

      masked.scan(HEADER) do |match|
        next if match.begin(0) < enclosing_end
        opening = match.end(0) - 1
        closing = lexer.matching_delimiter(opening)
        next unless closing
        enclosing_end = closing
        next unless match[3] == "class"

        attributes = [] of String
        match[1].scan(/(?:\[|,)\s*(?:global::)?(?:\w+\.)*(\w+)\s*(?=[(,\]])/) do |attribute|
          attributes << attribute[1].rchop("Attribute")
        end
        tail = match[5]
        base = tail.match(/\A\s*(?:<[^>]*>)?\s*(?:\([^)]*\))?\s*:\s*((?:global::)?[\w.]+)/).try(&.[1])
        start = match.begin(0)
        types << CSharpType.new(
          match[4], base.try(&.split('.').last.sub(/^global::/, "")),
          attributes, match[2].split, tail.lstrip.starts_with?('<'),
          source[start..closing], source[0...start].count('\n')
        )
      end
      types
    end
  end
end
