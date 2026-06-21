require "../models/endpoint"
require "./pattern_definition"

module NoirAIContext
  # Stateless detection engine. Given a callee / parameter name and/or
  # a source snippet, matches them against `PatternDefinition` sets and
  # produces `AIContextEntry` hits. Pure functions — no per-run state —
  # so `Builder` invokes them as module methods.
  module PatternMatcher
    # Maximum length of an AI-context display label before it is
    # compacted or truncated.
    MAX_LABEL_CHARS = 64

    extend self

    def detect_from_patterns(name : String,
                             snippet : String?,
                             patterns : Array(PatternDefinition),
                             path : String?,
                             line : Int32?,
                             source : String) : AIContextEntry?
      patterns.each do |pattern|
        if entry = detect_single_pattern(pattern, name, snippet, path, line, source)
          return entry
        end
      end

      nil
    end

    # Single-pattern variant of `detect_from_patterns`. Pulled out so
    # `add_source_scan_entries` can iterate every sink/validator
    # pattern independently (one match per kind), where the legacy
    # behaviour stopped at the first match across the whole list.
    def detect_single_pattern(pattern : PatternDefinition,
                              name : String,
                              snippet : String?,
                              path : String?,
                              line : Int32?,
                              source : String) : AIContextEntry?
      return if suppress_pattern_detection?(pattern.kind, name, snippet)

      name_match = name_match_text(name, pattern.name_patterns, pattern.kind)
      snippet_match = snippet_match_text(snippet, pattern.source_patterns)
      return unless name_match || snippet_match
      return if source == "callee" && name_match.nil?

      evidence_name = name_match || snippet_match || pattern.kind
      AIContextEntry.new(
        pattern.kind,
        evidence_name,
        source: source,
        description: pattern.description,
        path: path,
        line: line,
        confidence: source == "route_source" ? pattern.confidence - 12 : pattern.confidence,
        snippet: snippet
      )
    end

    def matches_any?(name : String, patterns : Array(Regex)) : Bool
      patterns.any? { |pattern| name.matches?(pattern) }
    end

    private def suppress_pattern_detection?(kind : String, name : String, snippet : String?) : Bool
      case kind
      when "sql"
        return true if name.matches?(/\b(URL\.Query|QueryParam|request\.query|req\.query|query_params|searchParams)\b/i)
        return true if snippet && snippet.matches?(/\b(URL\.Query\(\)\.Get|QueryParam\(|request\.query\.|req\.query\.|searchParams\.get)\b/i)
        # `<client>.query` is already surfaced as a `data_store_query` sink;
        # suppress the broader `sql` `\bquery\b` match so the same callee does
        # not emit two near-identical sinks.
        return true if name.matches?(/\b(?:mongo|client|neo4jClient)\.query\b/i)
      when "template_render"
        return true if name.matches?(/(?:^|\.)template\.(?:find|findAll|findById|count|save|insert|update|delete|remove)\b/i)
        return false unless snippet
        return true if snippet.matches?(/\brender\s+(json|plain|xml|body|status):/i)
        return true if snippet.matches?(/\brespond(Text|Bytes|File|Json|Redirect)\b/)
      when "outbound_http"
        return true if name.starts_with?("request.")
        return true if name == "request"
        return true if name.matches?(/(?:^|\.)(?:client|databaseClient)\.(?:query|insert|select|execute|sql|bind)\b/i)
      when "crypto_weak"
        # Weak hash primitives are common for non-security uses (cache
        # keys, ETags, file fingerprints). Only flag when the snippet
        # also mentions a security-relevant identifier — keeps the
        # signal noise down for codebases that hash file paths or
        # serialize cache state.
        return true unless snippet
        return false if snippet.matches?(/\b(password|passwd|secret|token|session|sign(ature)?|nonce|otp|mfa|2fa|cred(ential)?|jwt|hmac|salt|api[_-]?key)\b/i)
        return false if snippet.matches?(/\b(verification|activation|reset)(?:[_-]?(code|token))?/i)
        # AES/ECB and RC4 are weak regardless of context — keep the
        # snippet match alone good enough for those.
        return !snippet.matches?(/\bAES\/ECB\b|\bMode::ECB\b|\bRC4\b|\b['"]DES['"]?\b/)
      when "code_eval"
        return false unless snippet
        # `compile(..., 'exec')` already has an explicit 'exec' marker
        # in our regex; bare `compile()` from JSON/template tooling
        # must not collide. Keep the targeted patterns above and skip
        # generic compile() calls that didn't carry the 'exec' arg.
        return true if name == "compile"
      when "mass_assignment"
        return false unless snippet
        # If the snippet shows `.permit(` or `parse(`/`validate(` near
        # the suspect call, the developer already gated it. Skip the
        # warning in that case.
        return snippet.matches?(/\.permit\s*\(/) || snippet.matches?(/\.(parse|validate)\s*\(/i)
      when "uniqueness_validation"
        if name.matches?(/\b\w+(?:Repository|Repo|Dao)\.findBy(?!Id\b)(?!Id[A-Z])\w+\b/)
          return true unless snippet
          return !snippet.matches?(/\b(?:isEmpty|isNotEmpty|isPresent|AlreadyExist|Duplicate|Unique)\b/i)
        end
      end

      false
    end

    private def name_match_text(name : String, patterns : Array(Regex), kind : String) : String?
      return if name.empty?

      patterns.each do |pattern|
        if match = name.match(pattern)
          return normalize_label(name) if kind == "validation" && name.includes?(".")

          return normalize_label(match[0])
        end
      end

      nil
    end

    private def snippet_match_text(snippet : String?, patterns : Array(Regex)) : String?
      return unless snippet

      patterns.each do |pattern|
        if match = snippet.match(pattern)
          return normalize_label(expand_match_label(snippet, match))
        end
      end

      nil
    end

    # A source-scan regex usually matches only the leading anchor of a
    # construct (`Depends(get_current_` for the real
    # `Depends(get_current_active_superuser)`). Surfacing that truncated
    # fragment as the evidence name reads as a bug. Extend the match
    # rightward to finish a trailing identifier and to close a single
    # still-open `(`, so the label is the actual call. `normalize_label`
    # still caps the length, so a runaway argument list can't bloat it.
    private def expand_match_label(snippet : String, match : Regex::MatchData) : String
      start = match.begin
      finish = match.end
      return match[0] if start.nil? || finish.nil?

      while finish < snippet.size && (snippet[finish].alphanumeric? || snippet[finish] == '_')
        finish += 1
      end

      fragment = snippet[start...finish]
      open_parens = fragment.count('(') - fragment.count(')')
      if open_parens > 0
        depth = open_parens
        idx = finish
        while idx < snippet.size && depth > 0
          case snippet[idx]
          when '(' then depth += 1
          when ')' then depth -= 1
          end
          idx += 1
        end
        finish = idx
      end

      snippet[start...finish]
    end

    private def normalize_label(text : String) : String
      label = compact_function_signature_label(text) || text.split(/\s+\|\s+\d+:/, 2)[0]
      label = label.gsub(/\s+/, " ").strip
      label = compact_annotation_label(label) if label.size > MAX_LABEL_CHARS
      label[0, Math.min(label.size, MAX_LABEL_CHARS)]
    end

    private def compact_function_signature_label(label : String) : String?
      return unless label.matches?(/\s+\|\s+\d+:/)

      compacted = label.gsub(/\s+\|\s+\d+:\s*/, " ").gsub(/\s+/, " ").strip
      match = compacted.match(/^([A-Za-z_][A-Za-z0-9_.]*)\s*\((.*?)\)/)
      return unless match

      params = match[2]
        .gsub(/@[A-Za-z_][A-Za-z0-9_]*(?:\([^)]*\))?\s*/, "")
        .gsub(/\s*,\s*/, ", ")
        .gsub(/,\s*$/, "")
        .strip
      "#{match[1]}(#{params})"
    end

    private def compact_annotation_label(label : String) : String
      if match = label.match(/^(@[A-Za-z_][A-Za-z0-9_]*)(?:\([^)]*\))?\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_<>,.?]*)/)
        return "#{match[1]} #{match[2]}: #{match[3]}"
      end

      if match = label.match(/^(@[A-Za-z_][A-Za-z0-9_]*)(?:\([^)]*\))?\s+([A-Za-z_][A-Za-z0-9_<>,.?]*)\s+([A-Za-z_][A-Za-z0-9_]*)/)
        return "#{match[1]} #{match[3]}: #{match[2]}"
      end

      label
    end
  end
end
