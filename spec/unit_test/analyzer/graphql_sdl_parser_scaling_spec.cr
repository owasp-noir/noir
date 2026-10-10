require "../../spec_helper"
require "../../../src/analyzer/analyzers/specification/graphql_sdl_parser"

# Each root field recounted its line from the top of the document, and its
# name was matched by char offset (re-decoding a non-ASCII body from the
# start): an 8000-field Query took ~14s.
describe "GraphqlSdlParser root type scaling" do
  it "reads a large non-ASCII root type in linear time, on the right lines" do
    sdl = "# 한국어 스키마\ntype Query {\n" +
          (0...8000).join { |i| %(  "사용자 #{i}"\n  f#{i}(a#{i}: String): String\n) } + "}\n"
    endpoints = [] of Endpoint
    elapsed = Time.measure { endpoints = Analyzer::Specification::GraphqlSdlParser.parse(sdl, "schema.graphql") }

    endpoints.size.should eq(8000)
    last = endpoints.last
    last.url.should end_with("#Query.f7999")
    last.details.code_paths.first.line.should eq(3 + 7999 * 2 + 1)
    elapsed.should be < 2.seconds
  end
end
