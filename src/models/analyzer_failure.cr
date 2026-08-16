require "json"
require "yaml"

# One tech analyzer that raised and was skipped, named so the scan can say
# which part of the code base it never actually looked at.
#
# `analysis_endpoints` has always caught per-tech exceptions and kept going,
# which is the right call — one broken analyzer must not cost the user the
# other twenty. But the only trace was a warning line on stderr, so the
# result of a degraded scan was byte-identical to a clean one: "this project
# has no Go endpoints" and "the Go analyzer crashed before it could look"
# produced the same empty list and the same exit 0. In CI, where nobody reads
# the log of a green run, that is silent coverage loss.
#
# Carrying the failures into the structured output (and, with `--strict`,
# into the exit code) makes the difference observable.
struct AnalyzerFailure
  include JSON::Serializable
  include YAML::Serializable

  getter tech : String
  getter message : String

  def initialize(@tech : String, @message : String)
  end
end
