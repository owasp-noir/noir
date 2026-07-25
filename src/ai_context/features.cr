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

  def self.all_features : Set(String)
    FEATURES.to_set
  end

  # Parses a `--ai-context=…` value into the set of buckets that survive the
  # filter. An empty value, or one naming `all`, means every bucket.
  def self.parse_feature_set(raw : String) : Set(String)
    return all_features if raw.empty?

    filtered = Set(String).new
    raw.split(',').each do |feature|
      f = feature.strip
      next if f.empty?
      return all_features if f == FEATURE_ALL
      filtered << f
    end
    filtered
  end
end
