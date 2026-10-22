module Analyzer::Haskell
  # Shared helpers for the Haskell framework analyzers (Scotty, Servant).
  module Helper
    extend self

    # Blank out `--` line comments and nested `{- -}` block comments while
    # PRESERVING newlines/offsets, so a multi-line comment doesn't collapse
    # lines and shift every later endpoint's reported line number.
    def strip_haskell_comments(text : String) : String
      result = String::Builder.new
      chars = text.chars
      i = 0
      brace_depth = 0
      in_string = false

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == '"'
            in_string = false
            result << c
            i += 1
            next
          else
            result << c
            i += 1
            next
          end
        end

        if brace_depth == 0 && c == '"'
          in_string = true
          result << c
          i += 1
          next
        end

        if i + 1 < chars.size && c == '{' && chars[i + 1] == '-'
          brace_depth += 1
          result << ' '
          result << ' '
          i += 2
          while i < chars.size && brace_depth > 0
            if i + 1 < chars.size && chars[i] == '-' && chars[i + 1] == '}'
              brace_depth -= 1
              result << ' '
              result << ' '
              i += 2
            elsif i + 1 < chars.size && chars[i] == '{' && chars[i + 1] == '-'
              brace_depth += 1
              result << ' '
              result << ' '
              i += 2
            else
              result << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
          end
          next
        end

        if brace_depth == 0 && i + 1 < chars.size && c == '-' && chars[i + 1] == '-'
          while i < chars.size && chars[i] != '\n'
            i += 1
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end
  end
end
