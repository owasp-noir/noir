module Noir
  # Folds a call or subscript left open at a line end onto the line that
  # opens it, so a per-line accessor regex also sees a wrapped read
  # (`params.fetch(` / `:q` / `)`) as `params.fetch(:q)`.
  #
  # For the `#`-comment, `"`/`'`-string languages (Ruby, Crystal, Elixir).
  # Python has its own triple-quote-aware fold in `PythonEngine`.
  module CallFold
    extend self

    # A wrapped accessor read spans a handful of lines. A `(` still open
    # after this many is a long call (or a mis-scan, like a `(` in a regex
    # literal) and is left unfolded rather than glued onto far-away code.
    MAX_CONTINUATION_LINES = 10

    # `lines`, same size, each cut by the block (the language's comment
    # stripper) and rstripped. A line that leaves a `(` or `[` open is
    # followed by its (stripped) continuation lines, which also come back
    # as themselves, so a per-line scan over the result finds everything it
    # found on the comment-cut lines plus the wrapped reads.
    def fold(lines : Array(String), & : String -> String) : Array(String)
      cut = lines.map { |line| (yield line).rstrip }
      folded = cut.dup
      i = 0
      while i < cut.size
        head = cut[i]
        depth = delta(head)
        start = i
        i += 1
        next unless depth > 0

        last = head[-1]
        j = i
        joined = String.build do |io|
          io << head
          while j < cut.size && depth > 0 && j - start <= MAX_CONTINUATION_LINES
            piece = cut[j].lstrip
            j += 1
            next if piece.empty?
            # Glue the tokens back together, but keep `a` / `and b` two words.
            io << ' ' if word_char?(last) && word_char?(piece[0])
            io << piece
            last = piece[-1]
            depth += delta(piece)
          end
        end
        next if depth > 0 # unclosed: resume at the next line, which may open its own read

        folded[start] = joined
        i = j
      end
      folded
    end

    # `(` + `[` minus `)` + `]` outside `"` / `'` strings.
    private def delta(code : String) : Int32
      depth = 0
      quote = 0_u8
      escaped = false
      code.each_byte do |b|
        if quote != 0
          if escaped
            escaped = false
          elsif b == '\\'.ord
            escaped = true
          elsif b == quote
            quote = 0_u8
          end
        elsif b == '"'.ord || b == '\''.ord
          quote = b
        elsif b == '('.ord || b == '['.ord
          depth += 1
        elsif b == ')'.ord || b == ']'.ord
          depth -= 1
        end
      end
      depth
    end

    private def word_char?(ch : Char) : Bool
      ch.alphanumeric? || ch == '_'
    end
  end
end
