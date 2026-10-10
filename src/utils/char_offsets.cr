module Noir
  # Char <-> byte offsets and line numbers for one string, built in one pass.
  #
  # Analyzers that keep CHAR indices (to agree with the char-indexed masking
  # lexers) pay O(offset) for every `String#[]`, `String#match(re, pos)` and
  # `MatchData#begin/#end` once the string holds a single multi-byte char, and
  # `Analyzer#line_number_for_index` is O(offset) even on ASCII. Done per route
  # that is quadratic in the route count. These forms keep the char semantics
  # at O(1) / O(log n) per call.
  class CharOffsets
    getter content : String

    def initialize(@content : String)
      # PCRE2 re-validates the whole subject as UTF-8 on every match unless
      # told not to; done once here, so a per-route `match` stays O(match).
      @match_options = content.valid_encoding? ? Regex::MatchOptions::NO_UTF_CHECK : Regex::MatchOptions::None
      bytes = content.to_slice
      @newlines = [] of Int32
      i = 0
      while nl = bytes.index('\n'.ord.to_u8, i)
        @newlines << nl
        i = nl + 1
      end
      @starts = nil.as(Array(Int32)?)
      unless content.bytesize == content.size
        starts = Array(Int32).new(content.size + 1)
        reader = Char::Reader.new(content)
        while reader.has_next?
          starts << reader.pos
          reader.next_char
        end
        starts << content.bytesize
        @starts = starts
      end
    end

    # True when every char is one byte, so char and byte offsets coincide.
    def ascii? : Bool
      @starts.nil?
    end

    # `content.chars`, built on first use, for char-array scanners.
    getter chars : Array(Char) { @content.chars }

    # Byte offset of char index `char_pos`.
    def byte(char_pos : Int32) : Int32
      if starts = @starts
        starts[char_pos.clamp(0, starts.size - 1)]
      else
        char_pos.clamp(0, @content.bytesize)
      end
    end

    # Char index of byte offset `byte_pos` (a char boundary).
    def char(byte_pos : Int32) : Int32
      if starts = @starts
        starts.bsearch_index { |b| b >= byte_pos } || starts.size - 1
      else
        byte_pos
      end
    end

    # `content.match(regex, char_pos)`.
    def match(regex : Regex, char_pos : Int32, options : Regex::MatchOptions = Regex::MatchOptions::None) : Regex::MatchData?
      regex.match_at_byte_index(@content, byte(char_pos), options | @match_options)
    end

    # `content.index(regex, char_pos)`.
    def index(regex : Regex, char_pos : Int32, options : Regex::MatchOptions = Regex::MatchOptions::None) : Int32?
      match(regex, char_pos, options).try { |m| self.begin(m) }
    end

    # `content.index(char, char_pos)` for an ASCII `char`.
    def index(char : Char, char_pos : Int32) : Int32?
      @content.byte_index(char.ord.to_u8, byte(char_pos)).try { |b| self.char(b) }
    end

    # `content[char_pos]?`.
    def char_at(char_pos : Int32) : Char?
      return unless 0 <= char_pos < @content.size
      Char::Reader.new(@content, byte(char_pos)).current_char
    end

    # `match.begin(n)` / `match.end(n)` as char indices.
    def begin(match : Regex::MatchData, n : Int32 = 0) : Int32
      char(match.byte_begin(n))
    end

    def end(match : Regex::MatchData, n : Int32 = 0) : Int32
      char(match.byte_end(n))
    end

    # `content[from...to]`.
    def slice(from : Int32, to : Int32) : String
      start = byte(from)
      @content.byte_slice(start, byte(to) - start)
    end

    # Whether the char at `char_pos` is ASCII whitespace (false past the end).
    def ascii_whitespace?(char_pos : Int32) : Bool
      return false unless 0 <= char_pos < @content.size
      @content.to_unsafe[byte(char_pos)].unsafe_chr.ascii_whitespace?
    end

    # 1-based line of `char_pos`; same answer as `Analyzer#line_number_for_index`.
    def line(char_pos : Int32) : Int32
      return 1 if char_pos <= 0
      limit = byte(char_pos)
      (@newlines.bsearch_index { |nl| nl >= limit } || @newlines.size) + 1
    end
  end
end
