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

  # Clears AIContext buckets the user didn't request. Mirrors the
  # plain-text builder's feature filter so JSON/YAML/SARIF/Postman/
  # OAS — which serialize the struct directly — show the same
  # subset the user asked for via `--ai-context=guards,sinks`.
  # `features` follows the canonical bucket names: "guards",
  # "callee", "sources", "sinks", "validators", "signals". An empty set or
  # one containing every name is a no-op.
  def apply_feature_filter(endpoints : Array(Endpoint), features : Set(String))
    return endpoints if features.includes?("guards") &&
                        features.includes?("callee") &&
                        features.includes?("sources") &&
                        features.includes?("sinks") &&
                        features.includes?("validators") &&
                        features.includes?("signals")

    # Endpoint is a struct (value type). `endpoints.each` iterates
    # copies, so `endpoint.ai_context = …` would only mutate the
    # copy and leave the original array entry untouched. The array
    # bucket cleared on the copy *does* propagate because Array is
    # reference-typed, but the `= nil` assignment to drop the whole
    # context only sticks via index writeback.
    endpoints.each_with_index do |endpoint, idx|
      next if (context = endpoint.ai_context).nil?
      context.guards.clear unless features.includes?("guards")
      context.callees.clear unless features.includes?("callee")
      context.sources.clear unless features.includes?("sources")
      context.sinks.clear unless features.includes?("sinks")
      context.validators.clear unless features.includes?("validators")
      context.signals.clear unless features.includes?("signals")
      endpoint.ai_context = context.empty? ? nil : context
      endpoints[idx] = endpoint
    end
    endpoints
  end

  # Parses the comma-separated `--ai-context=…` value into the set
  # of bucket names that should survive the filter. Empty value or
  # `"all"` means every bucket (the no-op set).
  def parse_feature_set(raw : String) : Set(String)
    all = Set{"guards", "callee", "sources", "sinks", "validators", "signals"}
    return all if raw.empty?

    filtered = Set(String).new
    raw.split(',').each do |feature|
      f = feature.strip
      next if f.empty?
      return all if f == "all"
      filtered << f
    end
    filtered
  end
end
