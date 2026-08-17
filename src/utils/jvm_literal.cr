module Noir
  # The request-ready value a JVM-family (Java / Kotlin / Scala) default
  # expression evaluates to.
  #
  # A field initialiser or route default is *source*, not a value, and
  # `Param#value` is what every HTTP-shaped consumer puts on the wire — the
  # curl / httpie / PowerShell builders, the `--data-raw` JSON body, and the
  # OAS builders, which publish a non-empty value as an `enum` entry on the
  # parameter. So a default that has no literal form has no value either, and
  # passing the source text through produced things like
  # `{"slug":"title.toSlug()"}`, `{"addedAt":"LocalDateTime.now()"}` and
  # `/api/list-all?version=null`.
  #
  # Shared rather than per-analyzer because Kotlin's and Java's tree-sitter
  # parameter extractors and both Play routes analyzers were each about to
  # grow their own copy of the same three-line check, and two of them already
  # had byte-identical `normalize_route_default_value` bodies.
  module JvmLiteral
    extend self

    # Spellings of "no value": Java/Scala `null`, Kotlin/Scala `None`,
    # Scala/Groovy `Nil`/`nil`, and the empty-optional factories.
    ABSENT = %w[null None Nil nil Optional.empty Optional.empty() Option.empty Option.empty()]

    # Numeric literal type suffixes (`10L`, `1.5f`, `2.0d`). Stripped before
    # the numeric test so a suffixed literal is still recognised as one, and
    # emitted without the suffix — `?page=10L` is not a page number.
    NUMERIC_SUFFIXES = "LlFfDd"

    # Returns "" when `expr` is not a literal. Callers store the result
    # directly in `Param#value`, where "" already means "no value recorded".
    def value_of(expr : String) : String
      value = expr.strip
      return "" if value.empty?
      return "" if ABSENT.includes?(value)
      return value if value == "true" || value == "false"

      if value.size >= 2 && value[0] == value[-1] && value[0].in?('"', '\'')
        return value[1..-2]
      end

      # `to_f?` rather than the `String#numeric?` helper: that one is
      # monkey-patched onto ::String from inside `analyzers/python/fastapi.cr`,
      # so depending on it here would make this module compile or not
      # depending on which analyzer happened to be required first.
      numeric = value.delete('_')
      numeric = numeric[0..-2] if numeric.size > 1 && NUMERIC_SUFFIXES.includes?(numeric[-1])
      return numeric if !numeric.empty? && numeric.to_f?

      ""
    end
  end
end
