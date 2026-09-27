require "../../../../spec_helper"
require "../../../../../src/analyzer/analyzers/javascript/express/route_helper_scanner"

describe Analyzer::Javascript::RouteHelperScanner do
  # The gate must never reject a file the full pattern accepts: it is the
  # full pattern with the leading receiver dropped.
  it "gates the forwarded-call pattern on a necessary condition" do
    samples = [
      "router[verb](`/api${name}`, ...middlewares, handler)",
      "app.get(path, handler)",
      "r . post ( route , h )",
      "api\n  .delete(`/v1/x`, h)",
      "x.all(p, h)",
      "$app[method](target,",
      "obj.get(key)",
      "foo.fetch(url, opts)",
      "const a = [b](c, d)",
      "nothing here",
    ]
    samples.each do |sample|
      if sample.matches?(Analyzer::Javascript::RouteHelperScanner::FORWARD_CALL_RE)
        sample.matches?(Analyzer::Javascript::RouteHelperScanner::FORWARD_CALL_GATE).should be_true
      end
    end
    "obj.get(key)".matches?(Analyzer::Javascript::RouteHelperScanner::FORWARD_CALL_GATE).should be_false
  end
end
