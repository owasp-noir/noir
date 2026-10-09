require "file_utils"
require "../../../spec_helper"
require "../../../../src/analyzer/analyzers/specification/raml"
require "../../../../src/models/code_locator"
require "../../../../src/models/locator_keys"
require "../../../../src/models/skipped_files"

private def analyze_raml(base : String, entry : String) : Array(Endpoint)
  options = create_test_options
  options["base"] = YAML::Any.new([YAML::Any.new(base)])
  CodeLocator.instance.clear_all
  CodeLocator.instance.push(Noir::LocatorKeys::RAML_SPEC, entry)
  Analyzer::Specification::RAML.new(options).analyze
end

private def skip_messages : Array(String)
  Noir::SkippedFiles.failures(Noir::SkippedFiles::Phase::Analysis).map(&.message)
end

private def with_temp_dir(name : String, &)
  dir = File.tempname(name)
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

describe "RAML !include resolution" do
  before_each { Noir::SkippedFiles.clear }
  after_each do
    Noir::SkippedFiles.clear
    CodeLocator.instance.clear_all
  end

  it "cuts a resource include cycle and keeps the other resources" do
    with_temp_dir("noir_raml_cycle") do |dir|
      entry = File.join(dir, "api.raml")
      File.write(entry, "#%RAML 1.0\ntitle: T\n/x: !include res.raml\n/after:\n  get:\n")
      File.write(File.join(dir, "res.raml"), "get:\n/again: !include res.raml\n/more: !include res.raml\n")

      endpoints = analyze_raml(dir, entry)

      endpoints.map(&.url).sort!.should eq(["/after", "/x"])
      skip_messages.any?(&.includes?("include cycle")).should be_true
    end
  end

  it "stops a resource type whose own child is of that type" do
    with_temp_dir("noir_raml_type_cycle") do |dir|
      entry = File.join(dir, "api.raml")
      File.write(entry, <<-RAML)
        #%RAML 1.0
        title: T
        resourceTypes:
          T:
            get:
            /x:
              type: T
        /r:
          type: T
        /after:
          get:
        RAML

      endpoints = analyze_raml(dir, entry)

      endpoints.map(&.url).sort!.should eq(["/after", "/r", "/r/x"])
    end
  end

  it "refuses an include that resolves outside the scan base" do
    with_temp_dir("noir_raml_outside") do |dir|
      Dir.mkdir_p(File.join(dir, "api"))
      Dir.mkdir_p(File.join(dir, "outside"))
      File.write(File.join(dir, "outside", "secret.json"), %({"properties":{"leaked_secret_field":{}}}))
      entry = File.join(dir, "api", "api.raml")
      File.write(entry, <<-RAML)
        #%RAML 1.0
        title: T
        /a:
          post:
            body:
              application/json: !include ../outside/secret.json
        RAML

      endpoints = analyze_raml(File.join(dir, "api"), entry)

      endpoints.size.should eq(1)
      endpoints[0].params.map(&.name).should_not contain("leaked_secret_field")
      skip_messages.any?(&.includes?("outside the scan base")).should be_true
    end
  end
end
