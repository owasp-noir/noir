require "../../spec_helper"
require "../../../src/ai_context/features"
require "../../../src/options"

# `sources` is a fully implemented AI-context bucket: `apply_feature_filter`
# gates on it and every output builder emits it. But the CLI validator's
# vocabulary was a separate hand-written list that omitted it, so
# `--ai-context=sources` was rejected and `--ai-context=guards,sources` was
# unreachable — the bucket could only be obtained by asking for all of them.
# The help text disagreed too, listing a `callees` category that is spelled
# `callee` everywhere it is accepted.
#
# There is now one vocabulary. These specs pin the agreement.

describe "NoirAIContext::FEATURES" do
  it "is the vocabulary the CLI validates against" do
    # Not `should eq` on a literal list: the point is that the CLI derives
    # from the constant, so a bucket added in one place cannot be missing
    # from the other.
    AI_CONTEXT_FEATURES.should eq NoirAIContext::ACCEPTED_FEATURES
  end

  it "accepts every bucket plus the all alias, and nothing else" do
    NoirAIContext::ACCEPTED_FEATURES.sort.should eq(
      (NoirAIContext::FEATURES + ["all"]).sort
    )
    NoirAIContext::FEATURES.should_not contain "all"
  end

  it "includes sources" do
    NoirAIContext::FEATURES.should contain "sources"
    AI_CONTEXT_FEATURES.should contain "sources"
  end

  it "names callee in the singular, as the validator accepts it" do
    NoirAIContext::FEATURES.should contain "callee"
    NoirAIContext::FEATURES.should_not contain "callees"
  end
end

describe "NoirAIContext.parse_feature_set" do
  it "treats an empty value as every bucket" do
    NoirAIContext.parse_feature_set("").should eq NoirAIContext.all_features
  end

  it "treats all as every bucket, wherever it appears in the list" do
    NoirAIContext.parse_feature_set("all").should eq NoirAIContext.all_features
    NoirAIContext.parse_feature_set("guards,all").should eq NoirAIContext.all_features
  end

  it "narrows to the named buckets" do
    NoirAIContext.parse_feature_set("sources").should eq Set{"sources"}
    NoirAIContext.parse_feature_set("guards,sources").should eq Set{"guards", "sources"}
  end

  it "tolerates surrounding whitespace and empty entries" do
    NoirAIContext.parse_feature_set(" guards , ,sources ").should eq Set{"guards", "sources"}
  end

  # The CLI lowercases before storing, but a config-file `ai_context_features`
  # reaches the filter verbatim. Without folding here, `Guards` matched no
  # bucket and silently emptied every endpoint's AI context.
  it "matches bucket names case-insensitively" do
    NoirAIContext.parse_feature_set("Guards,SOURCES").should eq Set{"guards", "sources"}
    NoirAIContext.parse_feature_set("ALL").should eq NoirAIContext.all_features
  end
end

describe "NoirAIContext.unknown_features" do
  it "returns nothing for accepted names, in any case" do
    NoirAIContext.unknown_features("").should be_empty
    NoirAIContext.unknown_features("guards, sinks ,all").should be_empty
    NoirAIContext.unknown_features("Guards,SOURCES").should be_empty
  end

  it "echoes an unknown name in the spelling the user wrote" do
    NoirAIContext.unknown_features("Sinkz").should eq ["Sinkz"]
    NoirAIContext.unknown_features("guards,bogus,sinks").should eq ["bogus"]
  end
end
