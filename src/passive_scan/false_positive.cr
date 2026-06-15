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
      end

      false
    end

    # Decide whether a result on `line` for a rule of `category` should be
    # dropped as a false positive. Only `secret` findings are eligible;
    # everything else passes through unchanged.
    def self.suppress?(category : String, line : String) : Bool
      return false unless category == "secret"
      secret_reference?(line)
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
