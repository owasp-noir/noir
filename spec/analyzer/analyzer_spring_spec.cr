require "../../src/analyzer/analyzers/analyzer_spring.cr"
require "../../src/options"

describe "mapping_to_path" do
  options = default_options()
  instance = AnalyzerSpring.new(options)

  it "mapping_to_path - GET" do
    instance.mapping_to_path("@GetMapping(\"/abcd\")").should eq("/abcd")
  end
  it "mapping_to_path - POST" do
    instance.mapping_to_path("@PostMapping(\"/abcd\")").should eq("/abcd")
  end
end
