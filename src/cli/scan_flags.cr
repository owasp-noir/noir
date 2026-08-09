require "../ai_context/features"
require "../output_builder/formats"
require "../passive_scan/severity"

# The flag surface of `noir scan`, described once for every shell.
#
# Each of the four completion generators used to carry its own copy of this
# list — zsh with its `_arguments` specs, fish with `complete -l` lines,
# elvish with a flat `scan-flags` array, bash with the `SCAN_FLAGS` constant
# — so a new flag reached a user's shell only if whoever added it remembered
# all four. They had already drifted: `--ai-context` completed a bucket list
# that was missing `sources`, which the CLI has accepted for as long as the
# bucket has existed.
#
# The generators now render this table. What a shell can express varies (only
# zsh and fish attach descriptions, only bash needs the "flags that take a
# path" grouping), so each renderer reads the fields it can use and ignores
# the rest.
module Noir::CLI::ScanFlags
  # What follows the flag, and therefore how a shell should complete it.
  enum Arg
    None           # a switch
    Value          # takes a value nothing can usefully complete
    File           # takes a path
    Url            # takes a URL
    Choice         # takes one of `choices`
    OptionalChoice # `--flag` or `--flag=<one of choices>`

    def takes_value? : Bool
      self != None
    end
  end

  record Flag,
    long : String,
    description : String,
    arg : Arg = Arg::None,
    shorts : Array(String) = [] of String,
    # The word a shell shows in place of the value (`:path:`, `:severity:`).
    # Cosmetic, but it is the only hint zsh gives for a freeform value.
    hint : String = "value",
    choices : Array(String) = [] of String do
    # Short forms first, matching how every generator lists them.
    def names : Array(String)
      shorts + [long]
    end

    def takes_value? : Bool
      arg.takes_value?
    end

    def choice_list : String
      choices.join(" ")
    end
  end

  # Suggested `--include` values. The first three are the vocabulary
  # (`INCLUDE_TARGETS` in options.cr); the combined forms are there because
  # the flag is comma-separated and those two are what people actually type.
  INCLUDE_CHOICES = ["path", "techs", "callee", "path,techs", "path,techs,callee"]

  # Ordered as `noir scan --help` presents them, so a user tabbing through
  # the list sees the same grouping the help page uses.
  FLAGS = [
    Flag.new("--base-path", "Set base path", Arg::File, %w[-b], "path"),
    Flag.new("--url", "Set base URL for endpoints", Arg::Url, %w[-u], "URL"),
    Flag.new("--format", "Output format", Arg::Choice, %w[-f], "format", Noir::OutputFormats::NAMES),
    Flag.new("--output", "Write result to file", Arg::File, %w[-o], "path"),
    Flag.new("--pvalue", "Set parameter value TYPE=VAL", Arg::Value),
    Flag.new("--set-pvalue", "Set pvalue (any)", Arg::Value),
    Flag.new("--set-pvalue-header", "Set pvalue (header)", Arg::Value),
    Flag.new("--set-pvalue-cookie", "Set pvalue (cookie)", Arg::Value),
    Flag.new("--set-pvalue-query", "Set pvalue (query)", Arg::Value),
    Flag.new("--set-pvalue-form", "Set pvalue (form)", Arg::Value),
    Flag.new("--set-pvalue-json", "Set pvalue (json)", Arg::Value),
    Flag.new("--set-pvalue-path", "Set pvalue (path)", Arg::Value),
    Flag.new("--status-codes", "Display HTTP status codes"),
    Flag.new("--exclude-codes", "Exclude HTTP codes (comma-separated)", Arg::Value, hint: "codes"),
    Flag.new("--exclude-path", "Exclude files by glob", Arg::Value, hint: "pattern"),
    Flag.new("--include", "Enrich plain output (path,techs,callee)", Arg::Choice, hint: "list", choices: INCLUDE_CHOICES),
    Flag.new("--include-path", "Include source path column (legacy)"),
    Flag.new("--include-techs", "Include techs column (legacy)"),
    Flag.new("--include-callee", "Include callee column (legacy)"),
    Flag.new("--ai-context", "Include AI review context (guards,sinks,...)", Arg::OptionalChoice,
      hint: "list", choices: NoirAIContext::ACCEPTED_FEATURES),
    Flag.new("--no-color", "Disable color output"),
    Flag.new("--no-spinner", "Disable loading spinner animations"),
    Flag.new("--no-log", "Show only results"),
    Flag.new("--passive-scan", "Enable passive security scan", shorts: %w[-P]),
    Flag.new("--passive-scan-path", "Custom passive rules path", Arg::File, hint: "path"),
    Flag.new("--passive-scan-severity", "Min severity", Arg::Choice,
      hint: "severity", choices: PassiveScanSeverity::SEVERITY_LEVELS.keys),
    Flag.new("--passive-scan-auto-update", "Auto-update rules at startup"),
    Flag.new("--passive-scan-no-update-check", "Skip rule update check"),
    Flag.new("--use-all-taggers", "Activate all taggers", shorts: %w[-T]),
    Flag.new("--use-taggers", "Activate specific taggers", Arg::Value, hint: "list"),
    Flag.new("--probe", "Fire HTTP requests at endpoints"),
    Flag.new("--probe-via", "Route probes through proxy", Arg::Url, hint: "url"),
    Flag.new("--probe-header", "Header per probe", Arg::Value),
    Flag.new("--probe-match", "Only probe matching endpoints", Arg::Value),
    Flag.new("--probe-skip", "Skip matching endpoints", Arg::Value),
    Flag.new("--tls-skip-verify", "Skip TLS cert verification (insecure)"),
    Flag.new("--export-es", "Index endpoints in Elasticsearch", Arg::Url, hint: "url"),
    Flag.new("--export-opensearch", "Index endpoints in OpenSearch", Arg::Url, hint: "url"),
    Flag.new("--export-webhook", "POST endpoint catalog as JSON", Arg::Url, hint: "url"),
    Flag.new("--ai-provider", "AI provider prefix or URL", Arg::Value, hint: "provider"),
    Flag.new("--ai-model", "AI model name", Arg::Value, hint: "model"),
    Flag.new("--ai-key", "AI API key", Arg::Value, hint: "key"),
    Flag.new("--ai-agent", "Enable agentic AI workflow"),
    Flag.new("--ai-agent-max-steps", "Max steps for AI agent loop", Arg::Value, hint: "n"),
    Flag.new("--ai-native-tools-allowlist", "Provider allowlist for native tool-calling", Arg::Value, hint: "list"),
    Flag.new("--ai-max-token", "Max tokens per request", Arg::Value, hint: "n"),
    Flag.new("--diff-path", "Old code version for diff", Arg::File, hint: "path"),
    Flag.new("--techs", "Specify technologies", Arg::Value, %w[-t], "techs"),
    Flag.new("--exclude-techs", "Exclude technologies", Arg::Value, hint: "techs"),
    Flag.new("--only-techs", "Only run these tech detectors", Arg::Value, hint: "techs"),
    Flag.new("--config-file", "YAML config file", Arg::File, hint: "path"),
    Flag.new("--concurrency", "Concurrency level", Arg::Value, hint: "level"),
    Flag.new("--cache-disable", "Disable LLM cache for this run"),
    Flag.new("--cache-clear", "Clear LLM cache before scan"),
    Flag.new("--debug", "Enable debug messages", shorts: %w[-d]),
    Flag.new("--verbose", "Verbose mode"),
    # `-v`/`-V`/`--version` are rewritten to `noir version` by the router's
    # legacy layer rather than parsed by scan, but they are still typed in
    # scan position, so every shell completes them here.
    Flag.new("--version", "Show version", shorts: %w[-v -V]),
    Flag.new("--help", "Show help", shorts: %w[-h]),
  ]

  # Every spelling a user can type, short forms included.
  NAMES = FLAGS.flat_map(&.names)

  def self.with_arg(*kinds : Arg) : Array(Flag)
    FLAGS.select { |flag| kinds.includes?(flag.arg) }
  end

  # Flags whose value is a fixed vocabulary, i.e. the ones a shell can offer
  # candidates for rather than leaving the user to type.
  def self.with_choices : Array(Flag)
    with_arg(Arg::Choice, Arg::OptionalChoice)
  end

  # Flags whose value is a path or URL. Shells complete both from the
  # filesystem — a URL argument is often a `file://`-ish local target, and
  # offering nothing at all is worse than offering paths.
  def self.path_like : Array(Flag)
    with_arg(Arg::File, Arg::Url)
  end

  # Flags that take a value nothing can complete. Listed explicitly so a
  # shell can stop rather than fall through to filesystem completion, which
  # would suggest paths for `--techs`.
  def self.opaque_value : Array(Flag)
    with_arg(Arg::Value)
  end
end
