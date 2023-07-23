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
  it "mapping_to_path - code style1" do
    instance.mapping_to_path("@GetMapping(value = \"/abcd\")").should eq("/abcd")
  end
  it "mapping_to_path - code style2" do
    instance.mapping_to_path("@GetMapping({ \"/abcd\" })").should eq("/abcd")
  end
  it "mapping_to_path - requestmapping style1" do
    instance.mapping_to_path("@RequestMapping(value = \"/abcd\", method={RequestMethod.GET, RequestMethod.POST})").should eq("/abcd")
  end
  it "mapping_to_path - requestmapping style2" do
    instance.mapping_to_path("@RequestMapping(method={RequestMethod.GET, RequestMethod.POST}, value = \"/abcd\")").should eq("/abcd")
  end
end
