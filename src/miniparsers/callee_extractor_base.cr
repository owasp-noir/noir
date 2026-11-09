require "../models/endpoint"

module Noir
  # Shared skeleton for the per-language callee extractors. Each extractor is
  #
  #     module Noir::FooCalleeExtractor
  #       extend self
  #       include Noir::CalleeExtractorBase
  #       # ...language-specific scan_line / skip_callee? / regex tables...
  #     end
  #
  # and supplies only the language-specific scanning. The generic glue — the
  # Entry tuple shape and attaching collected callees to an endpoint — lives
  # here so a change to the Callee contract lands once instead of being
  # copy-pasted across every extractor.
  module CalleeExtractorBase
    # A discovered callee: (name, file path, 1-based line number).
    alias Entry = Tuple(String, String, Int32)

    # Attach collected callees to an endpoint as Callee records.
    def attach_to(endpoint : Endpoint, callees : Array(Entry))
      callees.each do |name, path, line|
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end
    end

    # `index` is a character offset (matches `source.chars` / `String#size`
    # indexing), not a UTF-8 byte offset.
    def line_number_for(chars : Array(Char), index : Int32) : Int32
      return 1 if index <= 0

      limit = index > chars.size ? chars.size : index
      count = 1
      i = 0
      while i < limit
        count += 1 if chars[i] == '\n'
        i += 1
      end
      count
    end

    private def scan_candidates(line : String, regex : Regex, candidates : Array(Tuple(Int32, String)))
      line.scan(regex) do |match|
        candidates << {match.begin(1) || 0, match[1]}
      end
    end

    private def read_identifier(chars : Array(Char), index : Int32, limit : Int32) : Tuple(String, Int32)
      cursor = index
      while cursor < limit && cursor < chars.size && identifier_part?(chars[cursor])
        cursor += 1
      end

      {chars[index...cursor].join, cursor}
    end

    private def identifier_start?(char : Char) : Bool
      char.ascii_letter? || char == '_'
    end

    private def identifier_part?(char : Char) : Bool
      char.ascii_alphanumeric? || char == '_'
    end

    # Skip a `'…'` / `"…"` literal opened at `index`, honouring `\` escapes.
    private def skip_short_string(chars : Array(Char), index : Int32, limit : Int32) : Int32
      quote = chars[index]
      cursor = index + 1
      escaped = false

      while cursor < limit && cursor < chars.size
        char = chars[cursor]
        if escaped
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          return cursor + 1
        end
        cursor += 1
      end

      limit
    end

    # Advance a byte offset past a line comment, stopping on its newline.
    private def skip_line_comment(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit && source.byte_at(i).unsafe_chr != '\n'
        i += 1
      end
      i
    end

    # Blank `chars[start_index...finish_index]`, keeping newlines so line
    # numbers stay aligned.
    private def append_blanks(builder : String::Builder, chars : Array(Char), start_index : Int32, finish_index : Int32)
      index = start_index
      while index < finish_index && index < chars.size
        builder << (chars[index] == '\n' ? '\n' : ' ')
        index += 1
      end
    end
  end
end
