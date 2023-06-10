require "../../src/analyzer/analyzers/analyzer_spring.cr"

describe "mapping_to_path" do
  it "mapping_to_path - GET" do
    mapping_to_path("@GetMapping(\"/abcd\")").should eq("/abcd")
  end
  it "mapping_to_path - POST" do
    mapping_to_path("@PostMapping(\"/abcd\")").should eq("/abcd")
  end
end
