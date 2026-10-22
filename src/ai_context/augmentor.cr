require "./features.cr"
require "../models/endpoint"
require "./pattern_definition"
require "./patterns"
require "./source_reader"
require "./pattern_matcher"
require "./builder"

# NoirAIContext enriches each endpoint with an `AIContext` — the
# guards / callees / sinks / validators / signals an LLM (or a human
# triage pass) needs to reason about the route. The heavy lifting
# lives in the collaborators required above:
#
#   * `PatternDefinition` / `Patterns` — the declarative detection
#     catalogs (sinks, validators, guards, parameter classes).
#   * `SourceReader`    — cached source reads + snippet extraction.
#   * `PatternMatcher`  — the stateless name/snippet detection engine.
#   * `Builder`         — orchestrates every populate step per endpoint.
#
# This file keeps only the public module surface: building context for
# a batch of endpoints, and the `--ai-context=…` feature filter.
module NoirAIContext
  extend self

  def apply(endpoints : Array(Endpoint)) : Array(Endpoint)
    Builder.new.apply(endpoints)
  end

  # Filters AIContext buckets while preserving evidence relationships for
  # derived signals. Mirrors the plain-text builder's feature filter so
  # JSON/YAML/SARIF/Postman/OAS and plain output show the same linked subset.
  # `features` holds bucket names from `NoirAIContext::FEATURES`. Selecting
  # every bucket is a no-op.
  def apply_feature_filter(endpoints : Array(Endpoint), features : Set(String))
    return endpoints if FEATURES.all? { |feature| features.includes?(feature) }

    # Endpoint is a struct (value type). `endpoints.each` iterates
    # copies, so `endpoint.ai_context = …` would only mutate the
    # copy and leave the original array entry untouched. The array
    # bucket cleared on the copy *does* propagate because Array is
    # reference-typed, but the `= nil` assignment to drop the whole
    # context only sticks via index writeback.
    endpoints.each_with_index do |endpoint, idx|
      next if (context = endpoint.ai_context).nil?
      selection = feature_selection_with_signal_evidence(
        features,
        context.signals.map { |signal| {signal.kind, signal.source} }
      )
      visible_features = selection[:features]
      context.signals.reject! { |signal| !selection[:signals].includes?(signal.kind) }
      context.guards.clear unless visible_features.includes?("guards")
      context.callees.clear unless visible_features.includes?("callee")
      context.sources.clear unless visible_features.includes?("sources")
      context.sinks.clear unless visible_features.includes?("sinks")
      context.validators.clear unless visible_features.includes?("validators")
      context.signals.clear unless visible_features.includes?("signals")
      endpoint.ai_context = context.empty? ? nil : context
      endpoints[idx] = endpoint
    end
    endpoints
  end
end
