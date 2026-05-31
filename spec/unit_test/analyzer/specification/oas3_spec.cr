require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/specification/oas3"

private def oas3_analyzer(url : String = "") : Analyzer::Specification::Oas3
  options = create_test_options
  options["url"] = YAML::Any.new(url)
  Analyzer::Specification::Oas3.new(options)
end

describe "OAS3 Analyzer" do
  it "prepends --url when an absolute server matches the target host" do
    servers = JSON.parse(%([{"url":"https://api.example.com/v1"}]))
    analyzer = oas3_analyzer("https://api.example.com")

    analyzer.get_base_path(servers).should eq("https://api.example.com/v1")
  end

  it "prepends --url to relative server paths and expands server variables" do
    servers = YAML.parse(<<-YAML
      - url: /api/{version}
        variables:
          version:
            default: v2
      YAML
    )
    analyzer = oas3_analyzer("https://api.example.com")

    analyzer.get_base_path(servers).should eq("https://api.example.com/api/v2")
  end

  it "uses --url as the fallback base when no server matches" do
    servers = JSON.parse(%([{"url":"https://other.example.com/v1"}]))
    analyzer = oas3_analyzer("https://api.example.com")

    analyzer.get_base_path(servers).should eq("https://api.example.com")
  end
end
