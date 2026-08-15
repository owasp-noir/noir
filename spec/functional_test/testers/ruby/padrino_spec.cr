require "../../func_spec.cr"

# The Gemfile here also declares `sinatra` (a realistic pin many real
# Padrino apps carry) to exercise `ruby_padrino`'s `:supersedes` over
# `ruby_sinatra`. Detection still sees both (`:techs => 2` below —
# `filter_redundant_generic_techs` only trims which *analyzer* runs, not
# the reported detection list; see the Lumen/Laravel tester for the same
# shape), but only the Padrino analyzer actually runs: every route the
# Sinatra analyzer would have found (the literal `get '/' do` /
# `get "/latest" do` routes below) still comes out, from the Padrino
# analyzer alone, with no duplicate reported under `ruby_sinatra`.
expected_endpoints = [
  Endpoint.new("/", "GET", [
    Param.new("query", "", "query"),
    Param.new("session", "", "cookie"),
  ]),
  Endpoint.new("/status", "GET"),
  Endpoint.new("/posts", "GET", [
    Param.new("page", "", "query"),
  ]),
  Endpoint.new("/posts/show/:id", "GET", [
    Param.new("id", "", "path"),
  ]),
  Endpoint.new("/posts/archive/:year", "GET", [
    Param.new("year", "", "path"),
  ]),
  Endpoint.new("/posts/create", "POST", [
    Param.new("HTTP_X_REQUEST_ID", "", "header"),
  ]),
  Endpoint.new("/posts/latest", "GET", [
    Param.new("limit", "", "query"),
  ]),
  Endpoint.new("/post/:post_id/comments", "GET", [
    Param.new("sort", "", "query"),
    Param.new("post_id", "", "path"),
  ]),
]

FunctionalTester.new("fixtures/ruby/padrino/", {
  :techs     => 2, # Detection sees ruby_padrino and ruby_sinatra (shared DSL signal)
  :endpoints => 8,
}, expected_endpoints).perform_tests

describe "Padrino analyzer filter" do
  it "drops ruby_sinatra when ruby_padrino is detected so the redundant pass is skipped" do
    filter_redundant_generic_techs(["ruby_padrino", "ruby_sinatra"]).should eq ["ruby_padrino"]
  end

  it "is order-independent" do
    filter_redundant_generic_techs(["ruby_sinatra", "ruby_padrino"]).should eq ["ruby_padrino"]
  end
end
