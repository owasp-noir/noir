require "../../../src/analyzer/analyzers/analyzer_spring.cr"
require "../../../src/options"

describe "mapping_to_path" do
  options = default_options()
  instance = AnalyzerSpring.new(options)

  it "mapping_to_path - GET" do
    instance.mapping_to_path("@GetMapping(\"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - POST" do
    instance.mapping_to_path("@PostMapping(\"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - PUT" do
    instance.mapping_to_path("@PutMapping(\"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - DELETE" do
    instance.mapping_to_path("@DeleteMapping(\"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - PATCH" do
    instance.mapping_to_path("@PatchMapping(\"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - code style1" do
    instance.mapping_to_path("@GetMapping(value = \"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - code style2" do
    instance.mapping_to_path("@GetMapping({ \"/abcd\" })").should eq(["/abcd"])
  end
  it "mapping_to_path - multiple path" do
    instance.mapping_to_path("@GetMapping(value={\"/abcd\", \"/efgh\"})").should eq(["/abcd", "/efgh"])
  end
  it "mapping_to_path - url template style" do
    instance.mapping_to_path("@GetMapping(\"/{abcd}\")").should eq(["/{abcd}"])
  end
  it "mapping_to_path - ant-style" do
    instance.mapping_to_path("@GetMapping(\"/{abcd:[a-z]+}\")").should eq(["/{abcd:[a-z]+}"])
  end
  it "mapping_to_path - regular expression style" do
    instance.mapping_to_path("@GetMapping(\"/{number:^[0-9]+$}\")").should eq(["/{number:^[0-9]+$}"])
  end
  it "mapping_to_path - requestmapping style1" do
    instance.mapping_to_path("@RequestMapping(value = \"/abcd\", method={RequestMethod.GET, RequestMethod.POST})").should eq(["/abcd"])
  end
  it "mapping_to_path - requestmapping style2" do
    instance.mapping_to_path("@RequestMapping(method={RequestMethod.GET, RequestMethod.POST}, value = \"/abcd\")").should eq(["/abcd"])
  end
  it "mapping_to_path - requestmapping style3" do
    instance.mapping_to_path("@RequestMapping(value = \"/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\")").should eq(["/0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"])
  end
  it "mapping_to_path - requestmapping style4" do
    instance.mapping_to_path("@GetMapping()").should eq([""])
  end
  it "mapping_to_path - requestmapping style5" do
    instance.mapping_to_path("@RequestMapping(method = RequestMethod.GET)").should eq([""])
  end
  it "mapping_to_path - requestmapping style6" do
    instance.mapping_to_path("@RequestMapping(\"/abcd\", produces=[MediaType.APPLICATION_JSON_VALUE])").should eq(["/abcd"])
  end
end

describe "utils func" do
  options = default_options()
  instance = AnalyzerSpring.new(options)

  it "is_bracket - true" do
    instance.is_bracket("{abcd=1234}").should eq(true)
  end
  it "is_bracket - false" do
    instance.is_bracket("abcd=1234").should eq(false)
  end
  it "comma_in_bracket" do
    instance.comma_in_bracket("{abcd,1234}").should eq("abcd_BRACKET_COMMA_1234")
  end
end
