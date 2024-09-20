require "../../../src/models/noir.cr"
require "../../../src/options.cr"
require "../../../src/models/endpoint.cr"

describe "Initialize" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new("noir")
  runner = NoirRunner.new(options)

  it "getter - options" do
    tmp_options = runner.options
    tmp_options["base"].should eq(options["base"])
  end
end

describe "Methods" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new("noir")
  options["url"] = YAML::Any.new("https://www.hahwul.com")
  options["nolog"] = YAML::Any.new(true)
  runner = NoirRunner.new(options)

  runner.endpoints << Endpoint.new("/abcd", "GET")
  runner.endpoints << Endpoint.new("abcd", "GET")

  it "combine_url_and_endpoints" do
    runner.combine_url_and_endpoints
    runner.endpoints[0].url.should eq("https://www.hahwul.com/abcd")
    runner.endpoints[1].url.should eq("https://www.hahwul.com/abcd")
  end
end

describe "set-pvalue" do
  config_init = ConfigInitializer.new
  options = config_init.default_options
  options["base"] = YAML::Any.new("noir")
  options["set_pvalue_query"] = YAML::Any.new([YAML::Any.new("FUZZ")])
  options["set_pvalue_header"] = YAML::Any.new([YAML::Any.new("name=FUZZ")])
  options["set_pvalue_cookie"] = YAML::Any.new([YAML::Any.new("name:FUZZ")])
  options["set_pvalue_json"] = YAML::Any.new([YAML::Any.new("name:FUZZ=FUZZ")])
  runner = NoirRunner.new(options)

  it "applies pvalue to query parameter" do
    runner.apply_pvalue("query", "name", "value").should eq("FUZZ")
  end
  
  it "applies pvalue to header parameter with '=' delimiter" do
    runner.apply_pvalue("header", "name", "value").should eq("FUZZ")
  end
  
  it "does not apply pvalue to header parameter when name does not match" do
    runner.apply_pvalue("header", "name2", "value").should eq("value")
  end
  
  it "applies pvalue to cookie parameter with ':' delimiter" do
    runner.apply_pvalue("cookie", "name", "value").should eq("FUZZ")
  end
  
  it "does not apply pvalue to cookie parameter when name does not match" do
    runner.apply_pvalue("cookie", "name2", "value").should eq("value")
  end
  
  it "includes '=' in the pvalue for JSON parameter" do
    runner.apply_pvalue("json", "name", "value").should eq("FUZZ=FUZZ")
  end
end
