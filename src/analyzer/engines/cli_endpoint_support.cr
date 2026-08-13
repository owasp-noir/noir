require "../../models/endpoint"

# Shared by the 21 `src/analyzer/analyzers/{lang}/cli.cr` analyzers, which all
# build the same thing: a set of `cli://<binary>` endpoints keyed by URL, so
# that flags and env vars discovered in different files merge onto one command.
#
# It is a mixin rather than an inherited method because the CLI analyzers have
# no common base below `Analyzer`: 17 extend `Analyzer` directly, while the Go,
# JavaScript, Python and Ruby ones extend their language engine. Pushing this
# onto `Analyzer` itself would hand a `cli://`-specific constructor to all ~200
# analyzers, so the mixin is included by exactly the 21 that want it.
#
# Deliberately just this one method. The other helpers those files carry —
# `cli_test_path?`, `cli_binary_name`, `cli_evidence?` — each read a per-class
# constant whose *value* differs by language (Perl's test tree is `/t/`, Scala's
# is `/it/`, Groovy's is `spec.groovy`; the binary-name stem lists disagree too).
# Several are therefore textually identical while resolving to different
# regexes, so folding them on name would be a silent behaviour change. They stay
# where they are.
module CliEndpointSupport
  # Fetches (or lazily creates) the endpoint for a URL, so flags scattered
  # across files/blocks merge onto one command.
  private def fetch_endpoint(endpoints : Hash(String, Endpoint), url : String,
                             path : String, line_no : Int32) : Endpoint
    endpoints[url] ||= begin
      ep = Endpoint.new(url, "CLI", Details.new(PathInfo.new(path, line_no)))
      ep.protocol = "cli"
      ep
    end
  end
end
