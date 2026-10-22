module NoirAIContext
  # The `--ai-context` bucket vocabulary, in emission order.
  #
  # There used to be four copies of this list — two in `options.cr` (the CLI
  # help text and the validator), one in `NoirAIContext.parse_feature_set`,
  # one in `OutputBuilderCommon#ai_context_feature_filter` — and they
  # disagreed. `sources` was in the two that decide what gets *emitted* and
  # missing from the two that decide what the CLI *accepts*, so
  # `--ai-context=sources` was rejected for a bucket the augmentor and every
  # output builder fully implement. The only way to see sources was to ask
  # for all of them, and `--ai-context=guards,sources` was unreachable.
  #
  # Anything that needs the vocabulary reads it here.
  FEATURES = %w[guards callee sources sinks validators signals]

  # Accepted from the user as "every bucket". Not a bucket itself, so it is
  # kept out of `FEATURES` and added back only where user input is validated.
  FEATURE_ALL = "all"

  # Every name `--ai-context=` accepts, including the `all` alias.
  ACCEPTED_FEATURES = FEATURES + [FEATURE_ALL]

  # Derived signals can depend on entries stored in another bucket. Keep
  # those evidence buckets visible whenever the signal is visible, and keep
  # only signals linked to the originally requested buckets. This preserves
  # relationships such as `ssrf` + `outbound_http` without exposing unrelated
  # signals from the same endpoint.
  SIGNAL_FEATURE_DEPENDENCIES = {
    "authz_absence"            => %w[guards sources],
    "guard_absence"            => %w[guards],
    "csrf_exempt"              => %w[guards],
    "idor_review"              => %w[guards sources],
    "rate_limit_absence"       => %w[guards sources],
    "ssrf"                     => %w[sinks sources],
    "open_redirect"            => %w[sinks sources],
    "path_traversal"           => %w[sinks sources],
    "priority_review"          => %w[guards sinks validators],
    "log_injection"            => %w[sources],
    "object_lookup"            => %w[callee sources],
    "object_write"             => %w[callee sources],
    "unsafe_method"            => %w[callee],
    "foreign_identifier_write" => %w[callee sources validators],
    "deep_link_input"          => %w[sources],
    "server_secret_source"     => %w[sources],
  }

  def self.all_features : Set(String)
    FEATURES.to_set
  end

  # Expands the requested features for signals present on this endpoint.
  # Explicitly requesting signals keeps them all; otherwise only signals
  # linked to the original selection are retained.
  def self.feature_selection_with_signal_evidence(features : Set(String), signals : Array(Tuple(String, String?)))
    visible_features = features.dup
    visible_signals = Set(String).new
    signals_requested = features.includes?("signals")

    signals.each do |kind, source|
      dependencies = SIGNAL_FEATURE_DEPENDENCIES[kind]? || [] of String
      dependencies = dependencies + ["sources"] if param_signal_source?(source)

      # The roll-up may reflect any mix of signals and sinks. Its possible
      # dependencies are useful when all signals are requested, but cannot
      # establish a relationship to one narrow feature selection.
      next if kind == "priority_review" && !signals_requested
      next unless signals_requested || dependencies.any? { |feature| features.includes?(feature) }

      visible_signals << kind
      dependencies.each { |feature| visible_features << feature }
    end

    visible_features << "signals" unless visible_signals.empty? || signals_requested
    {features: visible_features, signals: visible_signals}
  end

  private def self.param_signal_source?(source : String?) : Bool
    source == "param" || source.try(&.starts_with?("param_tagger:")) || false
  end

  # Parses a `--ai-context=…` value into the set of buckets that survive the
  # filter. An empty value, or one naming `all`, means every bucket.
  #
  # Names are case-folded to match the CLI, which lowercases before storing:
  # a config-file `ai_context_features: "Guards"` reaches here unmodified and
  # would otherwise match no bucket at all.
  def self.parse_feature_set(raw : String) : Set(String)
    return all_features if raw.empty?

    filtered = Set(String).new
    raw.split(',').each do |feature|
      f = feature.strip.downcase
      next if f.empty?
      return all_features if f == FEATURE_ALL
      filtered << f
    end
    filtered
  end

  # Names in `raw` that are outside the accepted vocabulary, in the user's
  # original spelling so an error message can echo the typo as written.
  #
  # `--ai-context=` validates through this; so does the effective option
  # value after config + CLI are merged. Without the second check a typo in
  # a config file's `ai_context_features` reached `parse_feature_set`,
  # matched no bucket, and silently emptied every endpoint's AI context —
  # the same value on the command line was a hard error.
  def self.unknown_features(raw : String) : Array(String)
    raw.split(',').map(&.strip).reject(&.empty?).reject do |feature|
      ACCEPTED_FEATURES.includes?(feature.downcase)
    end
  end
end
