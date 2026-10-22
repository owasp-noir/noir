require "../miniparsers/swift_callee_extractor"

module Noir
  # Brace-matched Swift body extraction shared by the iOS config analyzer
  # (enum case bodies) and the iOS deep-link linker (handler and method
  # bodies).
  module MobileSwiftBody
    # Finds the first `{` at/after the matched line (same line, else within a
    # few lines for a declaration whose parameter list and/or brace wrap onto
    # their own lines — a folded multi-line signature can run several lines
    # before the body brace).
    def find_opening_brace(lines : Array(String), start : Int32) : NamedTuple(index: Int32, col: Int32)?
      idx = start
      while idx < lines.size && idx <= start + 6
        col = lines[idx].index('{')
        return {index: idx, col: col} if col
        idx += 1
      end
      nil
    end

    # Brace-matched body text starting just after lines[opening_index][col],
    # handling both a compact single-line body (`{ case a, b, c }`) and a
    # multi-line one. Depth is tracked on `strip_non_code_with_state`'s
    # output (comments AND string contents blanked) so a raw value or
    # comment that contains `//` or unbalanced braces can't be mistaken for
    # real source structure and corrupt where the body actually ends.
    def body_after_opening_brace(lines : Array(String), opening_index : Int32, col : Int32) : Tuple(String, Int32)
      first = lines[opening_index][(col + 1)..]? || ""
      clean, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first, 0, false)
      brace = 1 + clean.count('{') - clean.count('}')
      if brace <= 0
        # Single-line body: trim the closing `}` and anything after it so a
        # trailing `.padding()` etc. doesn't leak into the body.
        closing = clean.rindex('}')
        return {closing ? first[0...closing] : first, opening_index + 1}
      end

      body = [first]
      idx = opening_index + 1
      while idx < lines.size && brace > 0
        line = lines[idx]
        stripped, depth, in_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, depth, in_string)
        nxt = brace + stripped.count('{') - stripped.count('}')
        if nxt <= 0
          closing = stripped.rindex('}')
          body << (closing ? line[0...closing] : line) unless line.strip == "}"
          break
        end
        body << line
        brace = nxt
        idx += 1
      end

      {body.join("\n"), opening_index + 1}
    end
  end
end
