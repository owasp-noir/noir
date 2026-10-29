# `Analyzer` must be the class before this file opens it as a namespace.
require "../../../models/analyzer"

module Analyzer::Python
  # Shared path helpers for the Python framework analyzers. Kept
  # framework-agnostic so each analyzer can opt in without duplicating
  # the slash-collapse / leading-slash conventions.
  module Helper
    extend self

    # Collapse repeated slashes and ensure a single leading slash.
    def normalize_path(path : ::String) : ::String
      normalized = path.gsub(/\/+/, "/")
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized
    end

    # `line` up to its first `#` outside a single-line quoted string.
    # Per-line like `python_delimiter_delta`: a line inside a multi-line
    # triple-quoted string is not recognised as such.
    def strip_python_comment(line : ::String) : ::String
      return line unless line.includes?('#')
      in_quote : Char? = nil
      escaped = false
      line.each_char_with_index do |ch, index|
        if in_quote
          if escaped
            escaped = false
          elsif ch == '\\'
            escaped = true
          elsif ch == in_quote
            in_quote = nil
          end
        elsif ch == '\'' || ch == '"'
          in_quote = ch
        elsif ch == '#'
          return line[0, index]
        end
      end
      line
    end

    def normalized_join(prefix : ::String, path : ::String) : ::String
      return normalize_path(path) if prefix.empty?
      return normalize_path(prefix) if path.empty?

      normalize_path("#{prefix}/#{path}")
    end

    # For each line, whether its first character sits inside a
    # triple-quoted string (i.e. a docstring opened on an earlier line).
    # A single linear scan tracks the open/close `"""`/`'''` delimiters at
    # file scope; single-line strings and `#` comments are skipped so a
    # stray `"""` inside them doesn't flip the state.
    #
    # Python API docs routinely spell a full worked example inside a
    # docstring — Superset's `superset_core/rest_api/decorators.py` shows
    # a `class MyExtensionAPI(RestApi)` with `@expose("/hello")` in prose —
    # and a line-oriented route scanner reads those as real routes.
    def docstring_line_flags(lines : Array(::String)) : Array(Bool)
      flags = Array(Bool).new(lines.size, false)
      in_triple = false
      triple_char = '\0'
      lines.each_with_index do |line, idx|
        flags[idx] = in_triple
        i = 0
        # `chars`, not `line[i]`: `String#[](Int)` walks from the start of
        # the string on every call once the content is not single-byte.
        chars = line.chars
        size = chars.size
        while i < size
          c = chars[i]
          if in_triple
            if c == triple_char && i + 2 < size && chars[i + 1] == triple_char && chars[i + 2] == triple_char
              in_triple = false
              i += 3
              next
            end
            i += 1
          elsif c == '#'
            break # comment runs to end of line
          elsif c == '"' || c == '\''
            if i + 2 < size && chars[i + 1] == c && chars[i + 2] == c
              in_triple = true
              triple_char = c
              i += 3
              next
            end
            # Single-line string: skip to its closing quote, consuming a
            # backslash and whatever follows it. An escape FLAG, not a
            # one-character lookback: a lookback cannot tell an escaped
            # quote from an escaped BACKSLASH followed by a quote.
            i += 1
            while i < size
              if chars[i] == '\\'
                i += 2
                next
              end
              break if chars[i] == c
              i += 1
            end
            i += 1
          else
            i += 1
          end
        end
      end
      flags
    end

    PYTHON_STRING_PIECE_RE = /\A\s*[rf]?(?:'([^']*)'|"([^"]*)")/

    # The leading string literal of `expression`, with Python's implicit
    # concatenation joined (`r"^a/" r"b/"` is one pattern) and a
    # parenthesised group of literals unwrapped (`(r"^a/" r"b/")`).
    def extract_python_string(expression : ::String) : ::String?
      rest = expression.strip
      parens = 0
      while rest.starts_with?('(')
        rest = rest[1..].lstrip
        parens += 1
      end
      value = nil
      while piece = rest.match(PYTHON_STRING_PIECE_RE)
        value = "#{value}#{piece[1]? || piece[2]}"
        rest = rest[piece[0].size..]
      end
      return value if value.nil? || parens == 0
      # Every opened `(` must close right after the literals; anything else
      # (`("a", b)`, `("a" % x)`) is not a plain string.
      parens.times do
        rest = rest.lstrip
        return unless rest.starts_with?(')')
        rest = rest[1..]
      end
      value
    end

    # `alias=` renames a parameter on the wire. Every Pydantic-backed Python
    # framework Noir supports spells it the same way — FastAPI's
    # `Header(alias=...)` / `Query(alias=...)`, django-ninja's identical
    # forms, and a `Field(alias=...)` on the body model behind either. With
    # the alias in force the identifier is no longer a name the app answers
    # to, so reporting it hands the next stage (cURL, OpenAPI, a DAST
    # import) a header or field the target rejects.
    #
    # Pydantic v2 splits the input side out as `validation_alias`, which
    # wins over a plain `alias` when both are present, so it is tried first.
    # `\b` keeps `\balias` from matching the tail of `validation_alias`.
    VALIDATION_ALIAS_RE = /\bvalidation_alias\s*=\s*(?:"([^"]*)"|'([^']*)')/
    ALIAS_RE            = /\balias\s*=\s*(?:"([^"]*)"|'([^']*)')/

    # Callers gate on having seen a real parameter-class call first, so a
    # default that merely contains the text `alias=` (`mode: str =
    # "alias=1"`) never reaches here.
    def declared_alias(declaration : ::String) : ::String?
      {VALIDATION_ALIAS_RE, ALIAS_RE}.each do |pattern|
        next unless match = declaration.match(pattern)
        name = match[1]? || match[2]?
        return name if name && !name.empty?
      end
      nil
    end
  end
end
