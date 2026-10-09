require "../../../spec_helper"
require "file_utils"
require "../../../../src/analyzer/analyzers/specification/oas3"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"

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

  it "ignores absolute servers with an empty host" do
    servers = JSON.parse(%([{"url":"https:///invalid"},{"url":"https://:443/also-invalid"},{"url":"https://api.example.com/v2"}]))

    oas3_analyzer.get_base_path(servers).should eq("/v2")
  end

  # With no usable `servers`, the base is `-u` itself; a trailing slash on it
  # produced `http://h//x`, which the optimizer passes through as absolute.
  it "joins a path onto a slash-terminated base with one slash" do
    dir = File.tempname("noir_oas3_slash")
    Dir.mkdir_p(dir)
    begin
      entry = File.join(dir, "openapi.yaml")
      File.write(entry, <<-YAML)
        openapi: 3.0.0
        info: {title: t, version: "1"}
        paths:
          /x:
            get:
              responses: {"200": {description: ok}}
        YAML
      CodeLocator.instance.clear_all
      CodeLocator.instance.push(Noir::LocatorKeys::OAS3_YAML, entry)
      options = create_test_options
      options["base"] = YAML::Any.new([YAML::Any.new(dir)])
      options["url"] = YAML::Any.new("http://h/")

      Analyzer::Specification::Oas3.new(options).analyze.map(&.url).should eq(["http://h/x"])
    ensure
      CodeLocator.instance.clear_all
      FileUtils.rm_rf(dir)
    end
  end
end
