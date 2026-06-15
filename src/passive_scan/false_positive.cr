require "../models/passive_scan"

module NoirPassiveScan
  # Heuristics that drop passive-scan results which trip a keyword/regex
  # matcher but are demonstrably *not* hard-coded secrets — chiefly
  # runtime indirections (environment-variable reads, CI templating
  # expressions) where the real value lives outside the source tree.
  #
  # Guiding invariant: **never hide a real literal.** Every form matched
  # here is one that *cannot* carry a checked-in secret — a
  # `${{ secrets.FOO }}` reference, an `os.getenv("FOO")` read, a
  # `<your-token>` placeholder — so suppressing it cannot turn a true
  # positive into a false negative. Anything that *could* be a literal
  # (an actual `ghp_…` token, a PEM block, a quoted high-entropy value)
  # is left untouched.
  #
  # Scope is intentionally narrow: only `secret`-category findings are
  # eligible. The dominant false-positive source for the bundled secret
  # rules is their `word` matcher firing on a variable *name*
  # (`GITHUB_TOKEN`, `AWS_ACCESS_KEY_ID`, …) on lines that merely
  # reference the variable rather than assign it a literal value.
  module FalsePositive
    # Runtime environment-variable accessors. A line that pulls its value
    # from the environment at runtime has, by construction, no literal
    # secret to leak. These are substring-matched anywhere on the line so
    # `key = os.getenv("OPENAI_API_KEY")` is covered regardless of where
    # the accessor sits.
    ENV_ACCESSOR_MARKERS = [
      "process.env",
      "import.meta.env",
      "os.environ",
      "os.getenv",
      "getenv(",
      "System.getenv",
      "System.getProperty",
      "Deno.env",
      "ENV[",
      "ENV.fetch",
      "Environment.GetEnvironmentVariable",
      "Sys.getenv",
    ]

    # Captures the value to the right of the first assignment separator
    # (`:`, `=`, or the PHP/Ruby hash arrow `=>`), trimming surrounding
    # whitespace. Lines with no assignment separator (e.g. a bare
    # `-----BEGIN RSA PRIVATE KEY-----`) never match, so PEM blocks and
    # similar literals fall through untouched.
    ASSIGNMENT_VALUE = /(?::|=>?)\s*(.+?)\s*$/

    # Same separators as ASSIGNMENT_VALUE but with an *empty* value —
    # `AWS_ACCESS_KEY_ID=` / `password:` in a `.env.example` or config
    # template. An empty value cannot carry a secret, so a keyword match
    # on such a line is always a false positive.
    EMPTY_ASSIGNMENT = /(?::|=>?)\s*$/

    # A secret *variable name*. The bundled secret rules carry two kinds
    # of `word` pattern: environment-variable names (`GITHUB_TOKEN`,
    # `DATABASE_URL`, `AWS_ACCESS_KEY_ID`) and literal secret markers
    # (`-----BEGIN PRIVATE KEY-----`). Only the former are eligible for
    # the "merely mentioned" suppression below — a PEM marker is itself
    # the secret and must never be dropped on a mention basis.
    #
    # Names are required to look like an env var: an identifier carrying
    # at least one uppercase letter or underscore (`DATABASE_URL`,
    # `github_pat_`). This deliberately excludes bare lowercase words
    # (`token`, `secret`) so a rule keyword that doubles as ordinary
    # prose is never suppressed on a mention basis — keeping the change
    # firmly on the false-positive-only side.
    SECRET_NAME = /\A(?=[A-Za-z0-9_]*[A-Z_])[A-Za-z_][A-Za-z0-9_]*\z/

    # Whole-line comment markers across the common languages noir scans
    # (shell/Python/Ruby/YAML `#`, C-family `//` `/*` `*`, HTML/XML/MD
    # `<!--`). A variable name *mentioned* in a comment is never a leaked
    # secret; a real literal in a comment is still caught by the
    # value-shape regex gate, so this can only drop false positives.
    COMMENT_PREFIXES = ["#", "//", "/*", "*", "<!--"]

    # Whole-value forms that are references or placeholders, never
    # literals: shell/template variable substitutions (`$VAR`, `${VAR}`,
    # `${{ … }}`, `$(…)`, `%VAR%`, `{{ … }}`), angle-bracket placeholders
    # (`<your-token>`), and single-argument env-helper calls
    # (`env('AWS_ACCESS_KEY_ID')`, common in Laravel/Symfony/Rails config).
    # Anchored so it only fires when the *entire* value is a reference — a
    # real secret that merely contains a `$` (e.g. `P$ssw0rd…`) is not
    # matched. The env-call form is deliberately single-argument: a
    # two-argument `env('K', 'default')` could hide a literal default, so
    # it is left to fall through.
    PURE_REFERENCE = /\A(?:\$\{?\{?[A-Za-z_][\w.\- ]*\}?\}?|\$\(.+\)|%[A-Za-z_]\w*%|\{\{.+\}\}|<[^>]+>|env\(\s*['"][^'",]+['"]\s*\))\z/

    # Documentation/template placeholder *values* — what a reader is told
    # to replace, never a real secret. Matched at the *start* of the value
    # so a `KEY=<token> …` or `KEY=your-access-key-id` example is caught
    # even with trailing text:
    #   - angle-bracket stubs (`<token>`, `<your-key>`)
    #   - `your-…` / `your_…` (`your-access-key-id`, `your_api_key`)
    #   - explicit "replace this" / "insert your" prose
    #   - bare null / dummy tokens (`nil`, `null`, `none`, `changeme`,
    #     `placeholder`, `redacted`, `xxxx…`, `****`)
    # All are forms a genuine high-entropy literal can never take, so this
    # only removes false positives.
    PLACEHOLDER_VALUE = /\A(?:<[^>]*>|your[-_ ]|insert[-_ ]your|replace[-_ ](?:me|this|with)|(?:changeme|change[-_]me|replaceme|replace[-_]me|placeholder|redacted|dummy|todo|fixme|none|null|nil|undefined|x{4,}|\*{4,})\b)/i

    # True when `line` exposes its secret-bearing value only through an
    # indirection (env read / templating) or a placeholder — i.e. there
    # is no literal secret on the line to leak.
    def self.secret_reference?(line : String) : Bool
      # GitHub Actions / templating expression anywhere on the line, e.g.
      # `GH_TOKEN: ${{ github.token }}` or `${{ secrets.GITHUB_TOKEN }}`.
      return true if line.includes?("${{")

      # Runtime environment-variable accessors.
      return true if ENV_ACCESSOR_MARKERS.any? { |marker| line.includes?(marker) }

      # Empty assignment value — `.env.example` / config template stub.
      return true if line.matches?(EMPTY_ASSIGNMENT)

      # Value position is itself a reference / placeholder.
      if match = line.match(ASSIGNMENT_VALUE)
        value = strip_wrapping_quotes(match[1])
        return true if value.matches?(PURE_REFERENCE)
        return true if value.matches?(PLACEHOLDER_VALUE)
      end

      false
    end

    # Decide whether a result on `line` for a rule of `category` should be
    # dropped as a false positive. Only `secret` findings are eligible;
    # everything else passes through unchanged. This category-only form is
    # the reference/placeholder check; the rule-aware overload below adds
    # matcher-type gating and the "merely mentioned" heuristic.
    def self.suppress?(category : String, line : String) : Bool
      return false unless category == "secret"
      secret_reference?(line)
    end

    # Rule-aware suppression. In addition to the reference/placeholder
    # check it gates on *which* matcher fired:
    #
    # - If a value-shape `regex` matcher hits the line, a real secret
    #   literal is present (`ghp_…`, `AKIA…`, a credentialed URL) — high
    #   confidence, never suppressed.
    # - Otherwise the finding is backed only by a `word` matcher on a
    #   variable *name*. When that name is merely *mentioned* — in a
    #   comment, a string literal, prose, a dependency list — rather than
    #   assigned a literal value, it is not a leaked secret.
    def self.suppress?(rule : PassiveScan, line : String) : Bool
      return false unless rule.category == "secret"

      # A value-shape regex match is the strongest signal — keep it.
      return false if regex_value_hit?(rule, line)

      # Runtime indirections / placeholders (env reads, `${{ }}`, empty
      # stubs, `env('NAME')`, `<placeholder>`).
      return true if secret_reference?(line)

      # Variable-name word match with no real assignment on the line.
      if name = matched_secret_name(rule, line)
        return true if comment_line?(line)
        return true unless assigns_literal?(line, name)
      end

      false
    end

    # True when any value-shape (`regex`) matcher of `rule` matches the
    # line — mirrors detect.cr's matching so the gate above agrees with
    # what actually fired.
    def self.regex_value_hit?(rule : PassiveScan, line : String) : Bool
      rule.matchers.each do |matcher|
        next unless matcher.type == "regex"
        next if matcher.regex_compile_failed?

        case matcher.condition
        when "or"
          if regex = matcher.compiled_regex
            return true if line.matches?(regex)
          end
        when "and"
          if regexes = matcher.compiled_regexes
            return true if !regexes.empty? && regexes.all? { |regex| line.matches?(regex) }
          end
        end
      end
      false
    end

    # The first env-var-name-shaped `word` pattern of `rule` that occurs
    # on the line, or nil. Literal markers like `-----BEGIN …-----` and
    # bare lowercase words are not env-var-shaped and are excluded.
    def self.matched_secret_name(rule : PassiveScan, line : String) : String?
      rule.matchers.each do |matcher|
        next unless matcher.type == "word"
        matcher.string_patterns.each do |pattern|
          next unless pattern.matches?(SECRET_NAME)
          return pattern if line.includes?(pattern)
        end
      end
      nil
    end

    # True when `line`'s leading non-space content is a comment marker.
    def self.comment_line?(line : String) : Bool
      stripped = line.lstrip
      COMMENT_PREFIXES.any? { |prefix| stripped.starts_with?(prefix) }
    end

    # True when `name` is assigned a (non-empty) value on the line —
    # `NAME=…`, `NAME: …`, `"NAME": …`, `NAME => …`. A bare mention
    # (`"DATABASE_URL"`, `env.delete("DATABASE_URL")`, prose) does not
    # match, so it is treated as a non-secret reference.
    def self.assigns_literal?(line : String, name : String) : Bool
      !!line.match(/#{Regex.escape(name)}['"]?\s*(?::|=>?)\s*\S/)
    end

    # Strip a single layer of matching wrapping quotes (and a trailing
    # comma, common in JSON/YAML) so `"${VAR}"` and `'$VAR',` reduce to
    # the bare reference before the PURE_REFERENCE check.
    private def self.strip_wrapping_quotes(value : String) : String
      v = value.rstrip(',')
      if v.size >= 2 && (v[0] == '"' || v[0] == '\'') && v[-1] == v[0]
        v = v[1...-1]
      end
      v
    end
  end
end
