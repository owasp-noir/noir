module Noir
  # Pure line-level helper for Python decorator-based framework adapters:
  # locates the `def`/`class` that a route decorator applies to. Route
  # decorators themselves are read by `TreeSitterPythonRouteExtractor`.
  module PythonRouteExtractor
    extend self

    # Locate the `def`/`async def`/`class` that a decorator applies to.
    #
    # `direction: :down` walks forward past additional decorators and blank
    # lines, stopping at the first non-decorator line (the one we want, or
    # something that breaks the decorator chain). `direction: :up` walks
    # backward, used when the decorator sits on a method whose enclosing
    # class was found elsewhere.
    #
    # Returns the index of the def/class line, or the original `line_index`
    # when nothing matches.
    def find_def_line(lines : Array(String), line_index : Int32, direction : Symbol = :down) : Int32
      case direction
      when :down
        # Carry the decorator line's paren depth forward so the walk
        # doesn't bail when it lands inside a multi-line decorator
        # call like `@app.route(\n  "/x",\n  methods=[...]\n)`.
        paren_depth = lines[line_index]? ? line_paren_delta(lines[line_index]) : 0
        i = line_index + 1
        while i < lines.size
          line = lines[i]
          stripped = line.lstrip
          if paren_depth <= 0 && (stripped.starts_with?("def ") || stripped.starts_with?("async def ") || stripped.starts_with?("class "))
            return i
          end
          # While still inside the decorator's call parens, every
          # continuation line is legal — accept it without checking
          # the @/#/blank rule.
          if paren_depth > 0
            paren_depth += line_paren_delta(line)
            i += 1
            next
          end
          # A comment between the decorator and the def is legal Python;
          # skip it along with blank lines and chained decorators.
          if stripped.starts_with?("@") || stripped.starts_with?("#") || stripped.empty?
            paren_depth += line_paren_delta(line)
            i += 1
            next
          end
          break
        end
      when :up
        i = line_index - 1
        while i >= 0
          stripped = lines[i].lstrip
          if stripped.starts_with?("def ") || stripped.starts_with?("async def ") || stripped.starts_with?("class ")
            return i
          end
          i -= 1
        end
      end
      line_index
    end

    # Net `(` − `)` count for a single line, ignoring parens inside
    # single- or double-quoted strings on the same line and comments
    # starting with `#`. Used by `find_def_line` to walk through
    # multi-line decorator headers without breaking the loop on
    # continuation tokens.
    private def line_paren_delta(line : String) : Int32
      depth = 0
      in_quote = nil
      escaped = false
      line.each_char do |ch|
        if in_quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
          next
        end
        case ch
        when '\'', '"'
          in_quote = ch
        when '#'
          break
        when '('
          depth += 1
        when ')'
          depth -= 1
        end
      end
      depth
    end
  end
end
