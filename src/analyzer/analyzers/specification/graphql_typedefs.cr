module Analyzer::Specification
  # Shared extractor for inline `typeDefs` template literals, used by the
  # Apollo Server and GraphQL Yoga analyzers. Returns `(SDL, line_offset)`
  # pairs — the SDL string carried by each `typeDefs` backtick template and
  # the 0-based source line where it begins.
  #
  # The whole scan runs over an `Array(Char)` rather than indexing the
  # `String` directly. `String#[](Int)` is O(n) whenever the source is not
  # single-byte-optimizable, so a single multi-byte char (an emoji in a
  # JS comment or a """description""") would otherwise make the per-char
  # template walk quadratic — ~6 s on a 120 KB file vs ~0.2 ms here.
  module GraphqlTypedefs
    extend self

    TYPEDEFS_PATTERN = /\btypeDefs\s*[:=]\s*/

    # `skip_js_comments` skips `/* GraphQL */` / `// ...` between the
    # assignment and the value — Yoga idiomatically annotates the literal
    # that way; Apollo does not, so it opts out.
    def extract(content : String, skip_js_comments : Bool = false) : Array(Tuple(String, Int32))
      results = [] of Tuple(String, Int32)
      chars = content.chars
      size = chars.size

      content.scan(TYPEDEFS_PATTERN) do |m|
        pos = (m.begin(0) || 0) + m[0].size
        pos = skip_tag(chars, pos)
        pos = skip_comments(chars, pos) if skip_js_comments

        next if pos >= size
        case chars[pos]
        when '['
          collect_in_brackets(chars, pos, results)
        when '`'
          collect_single(chars, pos, results)
        end
      end

      results
    end

    # Skips an optional `gql` / `graphql` tag function and trailing space.
    private def skip_tag(chars : Array(Char), pos : Int32) : Int32
      {"graphql", "gql"}.each do |tag|
        next unless starts_with_at?(chars, pos, tag)
        return skip_ws(chars, pos + tag.size)
      end
      pos
    end

    private def skip_comments(chars : Array(Char), pos : Int32) : Int32
      size = chars.size
      while pos < size
        ch = chars[pos]
        if ch.ascii_whitespace?
          pos += 1
          next
        end
        if ch == '/' && pos + 1 < size
          nxt = chars[pos + 1]
          if nxt == '/'
            pos += 2
            while pos < size && chars[pos] != '\n'
              pos += 1
            end
            next
          elsif nxt == '*'
            pos += 2
            while pos + 1 < size && !(chars[pos] == '*' && chars[pos + 1] == '/')
              pos += 1
            end
            pos += 2 if pos + 1 < size
            next
          end
        end
        break
      end
      pos
    end

    # Pull every backtick-delimited string from inside a `[...]` block.
    private def collect_in_brackets(chars : Array(Char), open_pos : Int32, results : Array(Tuple(String, Int32)))
      size = chars.size
      depth = 1
      pos = open_pos + 1
      while pos < size && depth > 0
        ch = chars[pos]
        case ch
        when '['
          depth += 1
          pos += 1
        when ']'
          depth -= 1
          pos += 1
        when '`'
          if extracted = extract_template_literal(chars, pos)
            sdl, next_pos = extracted
            results << {sdl, line_at(chars, pos) - 1}
            pos = next_pos
          else
            pos += 1
          end
        else
          pos += 1
        end
      end
    end

    private def collect_single(chars : Array(Char), backtick_pos : Int32, results : Array(Tuple(String, Int32)))
      return unless extracted = extract_template_literal(chars, backtick_pos)
      sdl, _ = extracted
      results << {sdl, line_at(chars, backtick_pos) - 1}
    end

    # Extracts a template literal starting at `\``, returning the interior
    # text (with `${...}` interpolations and escapes replaced by spaces so
    # that line counts and offsets stay aligned) and the position just past
    # the closing backtick.
    private def extract_template_literal(chars : Array(Char), start_pos : Int32) : Tuple(String, Int32)?
      return if start_pos >= chars.size || chars[start_pos] != '`'
      end_pos = find_closing_backtick(chars, start_pos + 1)
      return if end_pos.nil?
      {strip_interpolations(chars, start_pos + 1, end_pos), end_pos + 1}
    end

    private def find_closing_backtick(chars : Array(Char), start : Int32) : Int32?
      size = chars.size
      pos = start
      while pos < size
        ch = chars[pos]
        case ch
        when '`'
          return pos
        when '\\'
          pos += 2
        when '$'
          if pos + 1 < size && chars[pos + 1] == '{'
            depth = 1
            pos += 2
            while pos < size && depth > 0
              case chars[pos]
              when '{' then depth += 1
              when '}' then depth -= 1
              end
              pos += 1
            end
          else
            pos += 1
          end
        else
          pos += 1
        end
      end
      nil
    end

    private def strip_interpolations(chars : Array(Char), start : Int32, stop : Int32) : String
      String.build(stop - start) do |io|
        pos = start
        while pos < stop
          ch = chars[pos]
          if ch == '\\' && pos + 1 < stop
            io << ' '
            io << (chars[pos + 1] == '\n' ? '\n' : ' ')
            pos += 2
          elsif ch == '$' && pos + 1 < stop && chars[pos + 1] == '{'
            depth = 1
            pos += 2
            io << "  "
            while pos < stop && depth > 0
              c2 = chars[pos]
              case c2
              when '{' then depth += 1
              when '}' then depth -= 1
              end
              if depth == 0
                io << ' '
                pos += 1
                break
              end
              io << (c2 == '\n' ? '\n' : ' ')
              pos += 1
            end
          else
            io << ch
            pos += 1
          end
        end
      end
    end

    private def skip_ws(chars : Array(Char), pos : Int32) : Int32
      size = chars.size
      while pos < size && chars[pos].ascii_whitespace?
        pos += 1
      end
      pos
    end

    private def starts_with_at?(chars : Array(Char), pos : Int32, str : String) : Bool
      return false if pos + str.size > chars.size
      str.each_char_with_index do |c, i|
        return false if chars[pos + i] != c
      end
      true
    end

    private def line_at(chars : Array(Char), pos : Int32) : Int32
      return 1 if pos <= 0
      count = 0
      i = 0
      limit = pos > chars.size ? chars.size : pos
      while i < limit
        count += 1 if chars[i] == '\n'
        i += 1
      end
      count + 1
    end
  end
end
