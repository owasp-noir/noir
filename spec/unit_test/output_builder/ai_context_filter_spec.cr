require "../../spec_helper"
require "../../../src/output_builder/common"
require "../../../src/models/endpoint"
require "../../../src/utils/utils"

private def base_options(features : String = "")
  {
    "debug"               => YAML::Any.new(false),
    "verbose"             => YAML::Any.new(false),
    "color"               => YAML::Any.new(false),
    "nolog"               => YAML::Any.new(true),
    "output"              => YAML::Any.new(""),
    "include_techs"       => YAML::Any.new(false),
    "include_path"        => YAML::Any.new(false),
    "include_callee"      => YAML::Any.new(false),
    "ai_context"          => YAML::Any.new(true),
    "ai_context_features" => YAML::Any.new(features),
    "status_codes"        => YAML::Any.new(false),
    "exclude_codes"       => YAML::Any.new(""),
  }
end

private def endpoint_with_full_ai_context : Endpoint
  endpoint = Endpoint.new("/test", "GET")
  context = AIContext.new
  context.push_guard(AIContextEntry.new("guard", "auth_middleware", source: "tagger"))
  context.push_callee(AIContextEntry.new("callee", "save_record", source: "callee"))
  context.push_source(AIContextEntry.new("server_secret_source", "Spring @Value PASS -> password", source: "route_source"))
  context.push_sink(AIContextEntry.new("sql", "run_query", source: "callee"))
  context.push_validator(AIContextEntry.new("validation", "verify", source: "callee"))
  context.push_signal(AIContextEntry.new("route_definition", "GET /test", source: "route"))
  endpoint.ai_context = context
  endpoint
end

private def render(features : String) : String
  builder = OutputBuilderCommon.new(base_options(features))
  builder.io = IO::Memory.new
  builder.print([endpoint_with_full_ai_context])
  builder.io.to_s
end

# The plain-text ai_context block honors `ai_context_features` (Phase 6
# flag consolidation) so users can narrow `noir scan ... --ai-context
# guards,sinks` down to just the categories they care about.
describe "OutputBuilderCommon ai_context filter" do
  it "emits every category when ai_context_features is empty (default)" do
    output = render("")
    output.should contain("ai_context:")
    output.should contain("guards:")
    output.should contain("callees:")
    output.should contain("sources:")
    output.should contain("sinks:")
    output.should contain("validators:")
    output.should contain("signals:")
  end

  it "emits every category when ai_context_features is 'all'" do
    output = render("all")
    output.should contain("guards:")
    output.should contain("callees:")
    output.should contain("sources:")
    output.should contain("sinks:")
    output.should contain("validators:")
    output.should contain("signals:")
  end

  it "narrows to a single category" do
    output = render("guards")
    output.should contain("ai_context:")
    output.should contain("guards:")
    output.should_not contain("callees:")
    output.should_not contain("sources:")
    output.should_not contain("sinks:")
    output.should_not contain("validators:")
    output.should_not contain("signals:")
  end

  it "narrows to a comma-separated subset (guards + sinks)" do
    output = render("guards,sinks")
    output.should contain("guards:")
    output.should contain("sinks:")
    output.should_not contain("sources:")
    output.should_not contain("callees:")
    output.should_not contain("validators:")
    output.should_not contain("signals:")
  end

  it "uses 'callee' as the plain-text alias for the callees bucket" do
    output = render("callee")
    output.should contain("callees:")
    output.should_not contain("guards:")
    output.should_not contain("sinks:")
  end

  it "suppresses the ai_context: heading when the filter rejects every populated bucket" do
    options = base_options("guards")
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new

    endpoint = Endpoint.new("/test", "GET")
    context = AIContext.new
    # Only populate signals — the filter narrows to guards, so the
    # block has nothing visible and the heading should be omitted.
    context.push_signal(AIContextEntry.new("route_definition", "GET /test", source: "route"))
    endpoint.ai_context = context

    builder.print([endpoint])
    output = builder.io.to_s

    output.should_not contain("ai_context:")
    output.should_not contain("guards:")
  end

  it "does not emit ai_context at all when ai_context is disabled" do
    options = base_options("")
    options["ai_context"] = YAML::Any.new(false)
    builder = OutputBuilderCommon.new(options)
    builder.io = IO::Memory.new

    builder.print([endpoint_with_full_ai_context])
    output = builder.io.to_s

    output.should_not contain("ai_context:")
  end
end
