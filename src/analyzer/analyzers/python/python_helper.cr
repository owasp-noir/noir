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
