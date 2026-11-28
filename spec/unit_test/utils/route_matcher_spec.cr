require "../../spec_helper"
require "../../../src/utils/route_matcher"

private def regex_route(pattern : String, technology : String? = nil) : Endpoint
  endpoint = Endpoint.new(pattern, "GET")
  endpoint.kind = "regex"
  if technology
    details = Details.new
    details.technology = technology
    endpoint.details = details
  end
  endpoint
end

describe "Noir::RouteMatcher.trace" do
  # A scanned route can be any regular expression, and the traced path any
  # string. `(a|aa)+c` backtracks exponentially on `aaaa…c!`; past PCRE2's
  # match limit `matches?` raises `Regex::Error` instead of returning false.
  it "treats a route regex that exhausts the match limit as not matching" do
    matches = Noir::RouteMatcher.trace([regex_route("/(a|aa)+c")], "GET", "/" + "a" * 40 + "c!")

    matches.should be_empty
  end

  it "keeps matching a route regex that stays under the match limit" do
    route = regex_route("/re[0-9]+")

    matches = Noir::RouteMatcher.trace([route], "GET", "/re12")

    matches.map(&.endpoint.url).should eq([route.url])
    matches.first.matched_by.should eq("pattern")
  end

  it "keeps matching an exact route next to a regex that cannot be judged" do
    exact = Endpoint.new("/" + "a" * 40 + "c!", "GET")

    matches = Noir::RouteMatcher.trace([regex_route("/(a|aa)+c"), exact], "GET", exact.url)

    matches.map(&.endpoint.url).should eq([exact.url])
  end

  it "treats the case-folded pass over a route regex the same way" do
    route = regex_route("/(a|aa)+c", technology: "js_express")

    matches = Noir::RouteMatcher.trace([route], "GET", "/" + "a" * 40 + "c!")

    matches.should be_empty
  end
end
