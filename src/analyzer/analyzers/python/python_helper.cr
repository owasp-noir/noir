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

    def extract_python_string(expression : ::String) : ::String?
      string_match = expression.strip.match(/^[rf]?['"]([^'"]*)['"]/)
      string_match ? string_match[1] : nil
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
