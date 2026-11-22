module Noir::JvmDelimiter
  extend self

  # These call sites scan expressions in which only double quotes hide parens.
  def find_matching_paren(code : String, open_idx : Int32) : Int32?
    find_matching_delimiter(code, open_idx, '(', ')', quotes: %("))
  end

  # Index of the delimiter closing the `open_char` at `open_idx`, or nil when
  # the source runs out first. String and char literals are skipped, so a
  # `)`/`}` inside `"…"` or `'…'` cannot close the block early.
  #
  # Scan by CHARACTER (not byte): `open_idx` is a char index from
  # `String#index` and callers char-slice with — or range-compare — the
  # returned index. A byte scan corrupts both on multi-byte UTF-8.
  # ASCII-identical to the previous byte loop. The walk starts at
  # `open_idx` rather than skipping up to it from the file head, which
  # made one call per route quadratic over a large file.
  def find_matching_delimiter(code : String,
                              open_idx : Int32,
                              open_char : Char,
                              close_char : Char,
                              quotes : String = %("')) : Int32?
    depth = 1
    in_string = false
    quote = '\0'
    escape = false

    each_char_after(code, open_idx) do |ch, i|
      if in_string
        if escape
          escape = false
        elsif ch == '\\'
          escape = true
        elsif ch == quote
          in_string = false
        end
      else
        if quotes.includes?(ch)
          in_string = true
          quote = ch
        elsif ch == open_char
          depth += 1
        elsif ch == close_char
          depth -= 1
        end
      end
      return i if depth == 0
    end

    nil
  end

  # Yields each char after char index `index` with its char index.
  def each_char_after(code : String, index : Int32, &)
    return unless byte_index = code.char_index_to_byte_index(index + 1)
    reader = Char::Reader.new(code, byte_index)
    i = index + 1
    while reader.pos < code.bytesize
      yield reader.current_char, i
      reader.next_char
      i += 1
    end
  end
end
