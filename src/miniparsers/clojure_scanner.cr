module Noir
  # Low-level Clojure reader primitives, shared by the callee extractor in this
  # directory and by the Clojure framework analyzers, so the two never drift again.
  #
  # Every offset here is a *byte* offset into the raw source (`byte_at`), never a
  # character index, so the values stay usable with `String#byte_slice` on sources
  # containing non-ASCII text.
  module ClojureScanner
    extend self

    # Advance past a `;` line comment, stopping on the newline that ends it.
    def skip_comment(source : String, index : Int32, limit : Int32) : Int32
      i = index
      while i < limit && source.byte_at(i).unsafe_chr != '\n'
        i += 1
      end
      i
    end

    # Advance from the opening `"` of a string literal to its closing quote,
    # honouring `\` escapes. Returns the last in-range offset when the literal
    # is unterminated so callers still make progress.
    def skip_string(source : String, index : Int32, limit : Int32) : Int32
      i = index + 1
      escaping = false

      while i < limit
        char = source.byte_at(i).unsafe_chr
        if escaping
          escaping = false
        elsif char == '\\'
          escaping = true
        elsif char == '"'
          return i
        end
        i += 1
      end

      limit - 1
    end

    # Advance from the `\` that opens a character literal to the literal's last
    # byte (the same "last byte consumed" contract as `skip_string`).
    #
    # Clojure character literals are `\a`, `\"`, `\(`, `\\`, `\;` (a single
    # character, reader-significant ones included), the named forms `\newline`,
    # `\space`, `\tab`, `\formfeed`, `\backspace` and `\return`, `\uXXXX` and
    # `\oNNN`. Without this, `\"` opens a string that runs to the next quote in
    # the file and `\(` counts as a real open paren, so depth accounting — and
    # with it every route below the literal — collapses.
    def skip_char_literal(source : String, index : Int32, limit : Int32) : Int32
      # A trailing backslash at the very end of the range has nothing to consume.
      return index if index + 1 >= limit

      # The character right after the backslash always belongs to the literal,
      # whatever it is: in `\\` the escaped-looking backslash *is* the character
      # and the literal ends there, and `\;` is a semicolon, not a comment.
      last = index + 1

      # Named, unicode and octal literals run longer than one character. Take the
      # whole token so `\newline` cannot leave `ewline` behind to be read as a
      # symbol.
      if source.byte_at(last).unsafe_chr.ascii_alphanumeric?
        while last + 1 < limit && source.byte_at(last + 1).unsafe_chr.ascii_alphanumeric?
          last += 1
        end
      end

      last
    end

    # Advance past whitespace and `;` comments. Clojure reads commas as
    # whitespace; pass `commas: false` to stop on them.
    def skip_ws_and_comments(source : String, index : Int32, limit : Int32, commas : Bool = true) : Int32
      i = index
      while i < limit
        char = source.byte_at(i).unsafe_chr
        if char.whitespace? || (commas && char == ',')
          i += 1
        elsif char == ';'
          i = skip_comment(source, i, limit)
        else
          break
        end
      end
      i
    end

    # Find the offset of the delimiter closing the one at `index`, skipping over
    # comments, string literals and character literals so a `)` inside `";)"` or
    # a `\(` never moves the depth counter. Returns `index` unchanged when no
    # match is found.
    def find_matching_delimiter(source : String, index : Int32, open_char : Char, close_char : Char, limit : Int32) : Int32
      depth = 0
      i = index

      while i < limit
        char = source.byte_at(i).unsafe_chr
        case char
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          i = skip_string(source, i, limit)
        when '\\'
          i = skip_char_literal(source, i, limit)
        when open_char
          depth += 1
        when close_char
          depth -= 1
          return i if depth == 0
        end
        i += 1
      end

      index
    end

    # Line number of a byte offset, counted from `start_line` (1-based by
    # default, matching a whole-file offset).
    def line_number_for(source : String, index : Int32, start_line : Int32 = 1) : Int32
      start_line + source.to_slice[0, index].count('\n'.ord.to_u8)
    end

    CLOJURE_EXTENSIONS = {".clj", ".cljc", ".cljs"}

    def clojure_file?(path : String) : Bool
      CLOJURE_EXTENSIONS.any? { |ext| path.ends_with?(ext) }
    end

    # Read a bare symbol/keyword starting at `index`. Commas are whitespace in
    # Clojure, so by default they terminate a symbol just like spaces (keeps
    # `[x, y]` from reading `x,` as one token); pass `commas: false` to read
    # through them.
    def read_symbol(source : String, index : Int32, limit : Int32, commas : Bool = true) : Tuple(String, Int32)
      i = index
      while i < limit
        char = source.byte_at(i).unsafe_chr
        break if char.whitespace? || (commas && char == ',') || {'(', ')', '[', ']', '{', '}', '"', ';'}.includes?(char)
        i += 1
      end

      {source.byte_slice(index, i - index), i}
    end

    # Reads the next `(...)` / `[...]` / `{...}` form, `"..."` string or bare
    # symbol, returning its raw text and the offset after it (whitespace
    # skipped). `commas` is forwarded to `read_symbol` only.
    def read_form_token(source : String, start : Int32, limit : Int32, commas : Bool = true) : Tuple(String, Int32)
      i = skip_ws_and_comments(source, start, limit)
      return {"", i} if i >= limit

      case source.byte_at(i).unsafe_chr
      when '"'
        e = skip_string(source, i, limit)
        {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)}
      when '('
        e = find_matching_delimiter(source, i, '(', ')', limit)
        e > i ? {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)} : {"", i}
      when '['
        e = find_matching_delimiter(source, i, '[', ']', limit)
        e > i ? {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)} : {"", i}
      when '{'
        e = find_matching_delimiter(source, i, '{', '}', limit)
        e > i ? {source.byte_slice(i, e - i + 1), skip_ws_and_comments(source, e + 1, limit)} : {"", i}
      else
        read_symbol(source, i, limit, commas)
      end
    end

    # The first string literal before the next nested form, decoded, plus the
    # offset of its closing quote.
    def first_string_literal(source : String, index : Int32, limit : Int32) : Tuple(String?, Int32)
      i = skip_ws_and_comments(source, index, limit)
      while i < limit
        case source.byte_at(i).unsafe_chr
        when ';'
          i = skip_comment(source, i, limit)
        when '"'
          literal_end = skip_string(source, i, limit)
          return {decode_string_literal(source.byte_slice(i, literal_end - i + 1)), literal_end}
        when '(', '[', '{'
          break
        else
          i += 1
        end
      end

      {nil, i}
    end

    def decode_string_literal(raw : String) : String
      return raw unless raw.starts_with?('"') && raw.ends_with?('"') && raw.size >= 2

      inner = raw[1...raw.size - 1]
      inner.gsub(/\\(.)/, "\\1")
    end

    def base_symbol(symbol : String) : String
      parts = symbol.split('/')
      parts.last? || symbol
    end

    # `:name` segments of a route path, in order (duplicates kept).
    def extract_path_param_names(route_path : String) : Array(String)
      names = [] of String
      route_path.scan(/:([A-Za-z_][\w\-]*)/) do |match|
        names << match[1]
      end
      names
    end

    # A handler reference (`handler`, `#'ns/handler`, `'handler`) reduced to
    # its unqualified function name; nil for keywords, strings and literals.
    def normalized_handler_symbol(token : String) : String?
      name = token
      if name.starts_with?("#'")
        name = name[2..]
      elsif name.starts_with?('\'') || name.starts_with?('`')
        name = name[1..]
      end

      return unless handler_symbol?(name)
      function_name(name)
    end

    def handler_symbol?(token : String) : Bool
      return false if token.starts_with?(':')
      return false if token.starts_with?('"')
      return false if {"nil", "true", "false"}.includes?(token)
      !!token.match(/^[A-Za-z_.*+!?<>=][\w.\-*+!?<>=\/]*$/)
    end

    def function_name(symbol : String) : String
      if index = symbol.rindex('/')
        symbol[(index + 1)..]
      else
        symbol
      end
    end
  end
end
