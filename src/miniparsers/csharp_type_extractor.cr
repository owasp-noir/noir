require "../minilexers/csharp_lexer"

module Noir
  # One top-level `class` declaration, located by line range inside the file
  # the extractor was handed. The range (0-based, inclusive) spans the leading
  # attribute list through the closing brace, so a caller can slice the
  # lexer's own `code_lines`/`masked_lines` instead of re-lexing a substring.
  record CSharpType,
    name : String,
    base_name : String?,
    attributes : Array(String),
    modifiers : Array(String),
    generic : Bool,
    start_line : Int32,
    end_line : Int32

  module CSharpTypeExtractor
    HEADER = /((?:\[[^\]]*\]\s*)*)((?:(?:public|internal|private|protected|abstract|sealed|static|partial|new)\s+)*)(class|struct|interface|record)\s+(\w+)([^{};]*)\{/m

    ATTRIBUTE_NAME = /(?:\[|,)\s*(?:global::)?(?:\w+\.)*(\w+)\s*(?=[(,\]])/
    BASE_NAME      = /\A\s*(?:<[^>]*>)?\s*(?:\([^)]*\))?\s*:\s*((?:global::)?[\w.]+)/

    def self.extract(lexer : CSharpLexer) : Array(CSharpType)
      chars = lexer.masked
      types = [] of CSharpType
      enclosing_end = -1

      # Matches arrive in increasing `begin(0)` order and an accepted one
      # starts at or after the previous one's closing brace, so a single
      # forward cursor converts offsets to lines. `source[0...start].count`
      # would be O(n) per type — quadratic on a file full of classes, and
      # quadratic again on non-ASCII source where `String#[]` is O(n).
      cursor = 0
      line = 0
      line_at = ->(offset : Int32) do
        while cursor < offset
          line += 1 if chars[cursor] == '\n'
          cursor += 1
        end
        line
      end

      lexer.masked_source.scan(HEADER) do |match|
        next if match.begin(0) < enclosing_end
        opening = match.end(0) - 1
        closing = lexer.matching_delimiter(opening)
        next unless closing
        enclosing_end = closing
        next unless match[3] == "class"

        attributes = [] of String
        match[1].scan(ATTRIBUTE_NAME) do |attribute|
          attributes << attribute[1].rchop("Attribute")
        end
        tail = match[5]
        base = tail.match(BASE_NAME).try(&.[1])
        start_line = line_at.call(match.begin(0))
        types << CSharpType.new(
          match[4], base.try(&.split('.').last.sub(/^global::/, "")),
          attributes, match[2].split, tail.lstrip.starts_with?('<'),
          start_line, line_at.call(closing)
        )
      end
      types
    end
  end
end
